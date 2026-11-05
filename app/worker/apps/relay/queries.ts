// Relay's reads, shared by the app's routes and the AI connector (app/worker/relay-mcp/): each is capped, and each is
// SELECT only, so the connector can read every note and change none. A test fails on any other statement here.
import { MINUTE, type Db } from "./store.ts";

export type HealthType = "steps" | "heart_rate" | "sleep" | "workout";
/** A span from its first millisecond to the first one after it. */
export type Span = [number, number];

// lat, lon and place_from are set together: notes.ts takes lat and lon as a pair, and place.ts copies all three.
type Row = { id: string; source: "ring" | "typed"; text: string; recorded_at: number; device: string; audio: number;
  lat: number | null; lon: number | null; accuracy: number | null; place: string | null; place_from: "phone" | "history" | null };

const shaped = (row: Row) => ({ id: row.id, source: row.source, text: row.text, recordedAt: row.recorded_at, device: row.device,
  audio: row.audio === 1, place: row.lat === null ? null :
    { lat: row.lat, lon: row.lon!, accuracy: row.accuracy, name: row.place, from: row.place_from! } });

export type Note = ReturnType<typeof shaped>;

const NOTE = `SELECT n.id, n.source, n.text, n.recorded_at, d.name AS device, n.audio_key IS NOT NULL AS audio, n.lat, n.lon,
  n.accuracy, n.place, n.place_from FROM relay_notes n JOIN relay_devices d ON d.id = n.device_id`;

export type NoteFilter = { before?: number; beforeId?: string; after?: number; source?: "ring" | "typed"; words?: string[]; limit: number };

/** LIKE's own characters, escaped, so a word matches as typed. */
const like = (word: string) => `%${word.replace(/[\\%_]/g, "\\$&")}%`;

/** A page of notes, newest first, from `after` up to `before`, holding every word in `words` in any case. */
export async function notePage(db: Db, filter: NoteFilter) {
  const { before = Number.MAX_SAFE_INTEGER, beforeId = "", after = 0, source, words = [], limit } = filter;
  const where = ["(n.recorded_at < ? OR (n.recorded_at = ? AND n.id < ?))", "n.recorded_at >= ?",
    ...source ? ["n.source = ?"] : [], ...words.map(() => "n.text LIKE ? ESCAPE '\\'")];
  const { results } = await db.prepare(`${NOTE} WHERE ${where.join(" AND ")} ORDER BY n.recorded_at DESC, n.id DESC LIMIT ?`)
    .bind(before, before, beforeId, after, ...source ? [source] : [], ...words.map(like), limit + 1).all<Row>();
  const page = results.slice(0, limit);
  // Two notes can share a time, so a page ends at a time and an id: the next page starts just after both.
  const last = results.length > limit ? page.at(-1)! : null;
  return { notes: page.map(shaped), next: last?.recorded_at ?? null, nextId: last?.id ?? null };
}

export async function noteById(db: Db, id: string): Promise<Note | null> {
  const row = await db.prepare(`${NOTE} WHERE n.id = ?`).bind(id).first<Row>();
  return row && shaped(row);
}

// Spans arrive as one bound JSON array, numbered from 0 by json_each's key.
const SPANS = "WITH b (i, s, e) AS (SELECT key, json_extract(value, '$[0]'), json_extract(value, '$[1]') FROM json_each(?))";
const joined = (at: string, type: HealthType) => `FROM b JOIN relay_health h ON h.${at} >= b.s AND h.${at} < b.e WHERE h.type = '${type}'`;

/** Per device and source, then the largest: a phone and its watch that both count the day's steps don't double them. */
const largest = (type: HealthType, total: string, at: string) =>
  `${SPANS} SELECT i, MAX(total) AS total FROM (SELECT b.i, ${total} AS total ${joined(at, type)} GROUP BY b.i, h.device_id, h.source) GROUP BY i`;

const HEALTH: Record<HealthType, { sql: string; empty: Record<string, number | null> }> = {
  steps: { sql: largest("steps", "SUM(h.value)", "start_at"), empty: { total: 0 } },
  sleep: { sql: largest("sleep", `SUM(h.end_at - h.start_at) / ${MINUTE}`, "end_at"), empty: { total: 0 } },
  heart_rate: { sql: `${SPANS} SELECT b.i, MIN(h.value) AS min, MAX(h.value) AS max, ROUND(AVG(h.value)) AS average
    ${joined("start_at", "heart_rate")} GROUP BY b.i`, empty: { min: null, max: null, average: null } },
  workout: { sql: `${SPANS} SELECT b.i, COUNT(*) AS count, SUM(h.end_at - h.start_at) / ${MINUTE} AS minutes
    ${joined("start_at", "workout")} GROUP BY b.i`, empty: { count: 0, minutes: 0 } },
};

const ROUNDED = new Set(["total", "minutes"]);

/** One value per span: steps and sleep minutes as `total`, heart rate as min, max and average, workouts as a count
 *  and minutes. Sleep counts on the span it ends in, so a night belongs to the morning it ends. */
export async function healthBuckets(db: Db, type: HealthType, spans: Span[]): Promise<({ from: number; to: number } & Record<string, number | null>)[]> {
  const { results } = await db.prepare(HEALTH[type].sql).bind(JSON.stringify(spans)).all<{ i: number } & Record<string, number>>();
  const found = new Map(results.map(({ i, ...values }) => [i, values]));
  return spans.map(([from, to], index) => {
    const values = found.get(index) ?? HEALTH[type].empty;
    return { from, to, ...Object.fromEntries(Object.entries(values).map(([name, value]) =>
      [name, ROUNDED.has(name) ? Math.round(value!) : value])) };
  });
}

/** A place point's name: the phone's own, else its coordinates. */
const NAME = "COALESCE(place, printf('%.3f, %.3f', lat, lon))";

/** One day: how many notes, the health totals and the places visited, each place once. */
export async function daySummary(db: Db, from: number, to: number) {
  const spans: Span[] = [[from, to]];
  const [notes, [steps], [sleep], [heart], [workouts], places] = await Promise.all([
    db.prepare("SELECT COUNT(*) AS count FROM relay_notes WHERE recorded_at >= ? AND recorded_at < ?").bind(from, to).first<{ count: number }>(),
    healthBuckets(db, "steps", spans), healthBuckets(db, "sleep", spans), healthBuckets(db, "heart_rate", spans),
    healthBuckets(db, "workout", spans),
    db.prepare(`SELECT ${NAME} AS name, AVG(lat) AS lat, AVG(lon) AS lon, MIN(at) AS "from", MAX(at) AS "to"
      FROM relay_locations WHERE at >= ? AND at < ? GROUP BY 1 ORDER BY 4`).bind(from, to).all<{ name: string; lat: number; lon: number; from: number; to: number }>(),
  ]);
  return { notes: notes!.count, steps: steps.total!, sleepMinutes: sleep.total!,
    heartRate: heart.min === null ? null : { min: heart.min!, max: heart.max!, average: heart.average! },
    workouts: { count: workouts.count!, minutes: workouts.minutes! }, places: places.results };
}

type Visit = { name: string; lat: number; lon: number; arrived: number; left: number };

/** Visits from `from` to `to`, oldest first: each run of points at one place is one visit. `next` is the first
 *  visit left out, to read on from. */
export async function placeVisits(db: Db, from: number, to: number, limit: number) {
  const { results } = await db.prepare(`SELECT name, AVG(lat) AS lat, AVG(lon) AS lon, MIN(at) AS arrived, MAX(at) AS "left" FROM
      (SELECT *, SUM(moved) OVER (ORDER BY at, id) AS visit FROM
        (SELECT id, at, lat, lon, ${NAME} AS name, ${NAME} IS NOT lag(${NAME}) OVER (ORDER BY at, id) AS moved
          FROM relay_locations WHERE at >= ? AND at < ?))
    GROUP BY visit ORDER BY arrived LIMIT ?`).bind(from, to, limit + 1).all<Visit>();
  return { visits: results.slice(0, limit), next: results[limit]?.arrived ?? null };
}
