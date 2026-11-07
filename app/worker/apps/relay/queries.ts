// Relay's reads, shared by the app's routes and the AI connector (app/worker/relay-mcp/): each is capped, and each is
// SELECT only, so the connector can read every note and change none. A test fails on any other statement here.
import { MINUTE, type Db } from "./store.ts";

/** Every health type a phone sends, each in one unit: the one list POST health, the webhooks and the connector take. */
export const HEALTH_TYPES = ["steps", "heart_rate", "sleep", "workout", "weight", "resting_heart_rate", "hrv_sdnn", "hrv_rmssd",
  "blood_oxygen", "blood_pressure_systolic", "blood_pressure_diastolic", "cycle_flow", "mindful", "water"] as const;
export type HealthType = (typeof HEALTH_TYPES)[number];
/** A span from its first millisecond to the first one after it. */
export type Span = [number, number];

// lat, lon and place_from are set together: notes.ts takes lat and lon as a pair. A stored ring note may hold a place
// from location history, from before that was removed.
type Row = { id: string; source: "ring" | "typed"; text: string; recorded_at: number; device: string; audio: number;
  lat: number | null; lon: number | null; accuracy: number | null; place: string | null; place_from: "phone" | "history" | null;
  files: string };

/** A note's file: `ready` once the phone has sent its bytes, which GET attachment then opens. */
export type NoteFile = { id: string; name: string; type: string; size: number; ready: boolean };

const shaped = (row: Row) => ({ id: row.id, source: row.source, text: row.text, recordedAt: row.recorded_at, device: row.device,
  audio: row.audio === 1, place: row.lat === null ? null :
    { lat: row.lat, lon: row.lon!, accuracy: row.accuracy, name: row.place, from: row.place_from! },
  attachments: (JSON.parse(row.files) as (Omit<NoteFile, "ready"> & { ready: number })[]).map(file => ({ ...file, ready: file.ready === 1 })) });

export type Note = ReturnType<typeof shaped>;

const FILES = `(SELECT json_group_array(json_object('id', a.id, 'name', a.name, 'type', a.content_type, 'size', a.size,
  'ready', a.file_key IS NOT NULL)) FROM (SELECT * FROM relay_attachments WHERE note_id = n.id ORDER BY rowid) a) AS files`;
const NOTE = `SELECT n.id, n.source, n.text, n.recorded_at, d.name AS device, n.audio_key IS NOT NULL AS audio, n.lat, n.lon,
  n.accuracy, n.place, n.place_from, ${FILES} FROM relay_notes n JOIN relay_devices d ON d.id = n.device_id`;

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

/** Values over each span's readings, as `name AS column` parts; a span with none reads as nulls. */
const over = (type: HealthType, values: string[]) => ({ sql: `${SPANS} SELECT b.i, ${values.join(", ")} ${joined("start_at", type)} GROUP BY b.i`,
  empty: Object.fromEntries(values.map(value => [value.split(" AS ")[1], null])) });
const range = (type: HealthType) => over(type, ["MIN(h.value) AS min", "MAX(h.value) AS max", "ROUND(AVG(h.value)) AS average"]);
const average = (type: HealthType) => over(type, ["ROUND(AVG(h.value), 1) AS average"]);
const minutes = `SUM(h.end_at - h.start_at) / ${MINUTE}`;

const HEALTH: Record<HealthType, { sql: string; empty: Record<string, number | null> }> = {
  steps: { sql: largest("steps", "SUM(h.value)", "start_at"), empty: { total: 0 } },
  sleep: { sql: largest("sleep", minutes, "end_at"), empty: { total: 0 } },
  heart_rate: range("heart_rate"),
  workout: { sql: `${SPANS} SELECT b.i, COUNT(*) AS count, ${minutes} AS minutes
    ${joined("start_at", "workout")} GROUP BY b.i`, empty: { count: 0, minutes: 0 } },
  // The bare value beside MAX() is SQLite's: it comes from the row with the latest start.
  weight: { sql: `SELECT i, latest FROM (${SPANS} SELECT b.i, h.value AS latest, MAX(h.start_at) ${joined("start_at", "weight")} GROUP BY b.i)`,
    empty: { latest: null } },
  resting_heart_rate: average("resting_heart_rate"),
  hrv_sdnn: average("hrv_sdnn"),
  hrv_rmssd: average("hrv_rmssd"),
  blood_oxygen: over("blood_oxygen", ["MIN(h.value) AS min", "ROUND(AVG(h.value), 1) AS average"]),
  blood_pressure_systolic: range("blood_pressure_systolic"),
  blood_pressure_diastolic: range("blood_pressure_diastolic"),
  cycle_flow: over("cycle_flow", ["MAX(h.value) AS flow"]),
  mindful: { sql: largest("mindful", minutes, "start_at"), empty: { total: 0 } },
  water: { sql: largest("water", "SUM(h.value)", "start_at"), empty: { total: 0 } },
};

const ROUNDED = new Set(["total", "minutes"]);

/** One value per span, by the type's own values: steps as `total`, heart rate as min, max and average, and so on.
 *  Sleep counts on the span it ends in, so a night belongs to the morning it ends. */
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

/** Each blood pressure reading, upper and lower paired by device and time, oldest first, up to 20. */
async function pressures(db: Db, from: number, to: number) {
  const { results } = await db.prepare(`SELECT s.start_at AS at, s.value AS upper, d.value AS lower FROM relay_health s
    JOIN relay_health d ON d.device_id = s.device_id AND d.start_at = s.start_at AND d.type = 'blood_pressure_diastolic'
    WHERE s.type = 'blood_pressure_systolic' AND s.start_at >= ? AND s.start_at < ? GROUP BY s.device_id, s.start_at ORDER BY 1 LIMIT 20`)
    .bind(from, to).all<{ at: number; upper: number; lower: number }>();
  return results;
}

/** The day's other health values, each only when the day has some. */
async function dayHealth(db: Db, spans: Span[]) {
  const read = (type: HealthType) => healthBuckets(db, type, spans).then(([value]) => value);
  const [weight, resting, sdnn, rmssd, oxygen, flow, mindful, water] = await Promise.all((["weight", "resting_heart_rate", "hrv_sdnn",
    "hrv_rmssd", "blood_oxygen", "cycle_flow", "mindful", "water"] as const).map(read));
  return { ...weight.latest !== null && { weightKg: weight.latest }, ...resting.average !== null && { restingHeartRate: resting.average },
    ...sdnn.average !== null && { hrvSdnn: sdnn.average }, ...rmssd.average !== null && { hrvRmssd: rmssd.average },
    ...oxygen.min !== null && { bloodOxygen: { min: oxygen.min, average: oxygen.average! } },
    ...flow.flow !== null && { cycleFlow: flow.flow }, ...mindful.total! > 0 && { mindfulMinutes: mindful.total },
    ...water.total! > 0 && { waterMl: water.total } };
}

/** One day: how many notes, the health totals, the places visited, each place once, and the calendar's events. */
export async function daySummary(db: Db, from: number, to: number) {
  const spans: Span[] = [[from, to]];
  const [notes, [steps], [sleep], [heart], [workouts], more, bloodPressure, places, events] = await Promise.all([
    db.prepare("SELECT COUNT(*) AS count FROM relay_notes WHERE recorded_at >= ? AND recorded_at < ?").bind(from, to).first<{ count: number }>(),
    healthBuckets(db, "steps", spans), healthBuckets(db, "sleep", spans), healthBuckets(db, "heart_rate", spans),
    healthBuckets(db, "workout", spans), dayHealth(db, spans), pressures(db, from, to),
    db.prepare(`SELECT ${NAME} AS name, AVG(lat) AS lat, AVG(lon) AS lon, MIN(at) AS "from", MAX(at) AS "to"
      FROM relay_locations WHERE at >= ? AND at < ? GROUP BY 1 ORDER BY 4`).bind(from, to).all<{ name: string; lat: number; lon: number; from: number; to: number }>(),
    eventPage(db, { from, to, limit: DAY_EVENTS }),
  ]);
  return { notes: notes!.count, steps: steps.total!, sleepMinutes: sleep.total!,
    heartRate: heart.min === null ? null : { min: heart.min!, max: heart.max!, average: heart.average! },
    workouts: { count: workouts.count!, minutes: workouts.minutes! }, ...more, ...bloodPressure.length > 0 && { bloodPressure },
    places: places.results,
    events: events.events.map(({ title, start, end, allDay, people }) => ({ title, start, end, allDay, people: people.flatMap(person => person.name ?? []) })) };
}

// Calendar events from the phone: a removed one is kept for its webhooks, and no read shows it.
type EventRow = { id: number; calendar: string; title: string; start_at: number; end_at: number; all_day: number;
  location: string | null; notes: string | null; url: string | null; people: string; device: string };
export type Person = { name?: string; email?: string; organizer?: boolean };

const eventShaped = (row: EventRow) => ({ id: String(row.id), title: row.title, calendar: row.calendar, start: row.start_at,
  end: row.end_at, allDay: row.all_day === 1, location: row.location, notes: row.notes, url: row.url,
  people: JSON.parse(row.people) as Person[], device: row.device });

export type CalendarEvent = ReturnType<typeof eventShaped>;

/** At most this many events in one day's summary. */
export const DAY_EVENTS = 50;
const EVENT = `SELECT e.id, e.calendar, e.title, e.start_at, e.end_at, e.all_day, e.location, e.notes, e.url, e.people, d.name AS device
  FROM relay_calendar_events e JOIN relay_devices d ON d.id = e.device_id`;
/** A word in the title, place, notes or people. */
const EVENT_WORD = "(e.title LIKE ?1 ESCAPE '\\' OR e.location LIKE ?1 ESCAPE '\\' OR e.notes LIKE ?1 ESCAPE '\\' OR e.people LIKE ?1 ESCAPE '\\')";

export type EventFilter = { from: number; to: number; words?: string[]; limit: number; after?: { at: number; id: number } };

/** A page of events that overlap `from` to `to`. With words, the newest first, each holding every word; without, in
 *  start order. `after` is the last event of the page before. */
export async function eventPage(db: Db, filter: EventFilter) {
  const { from, to, words = [], limit, after } = filter;
  const newest = words.length > 0;
  const where = ["e.removed_at IS NULL", "e.start_at < ?1", "e.end_at > ?2 OR e.start_at >= ?2",
    ...after ? [newest ? "(e.start_at < ?3 OR (e.start_at = ?3 AND e.id < ?4))" : "(e.start_at > ?3 OR (e.start_at = ?3 AND e.id > ?4))"] : [],
    ...words.map((_, index) => EVENT_WORD.replaceAll("?1", `?${index + 6}`))];
  const order = newest ? "DESC" : "ASC";
  const { results } = await db.prepare(`${EVENT} WHERE ${where.map(part => `(${part})`).join(" AND ")}
    ORDER BY e.start_at ${order}, e.id ${order} LIMIT ?5`)
    .bind(to, from, after?.at ?? 0, after?.id ?? 0, limit + 1, ...words.map(like)).all<EventRow>();
  const page = results.slice(0, limit);
  const last = results.length > limit ? page.at(-1)! : null;
  return { events: page.map(eventShaped), next: last && { at: last.start_at, id: last.id } };
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

// Chats: each one's title is the newest save's, else the title of its first send. Neither the device nor Claude Code's
// session id leaves here.
type ChatRow = { id: string; title: string; project: string; app: "claude-code"; started_at: number; last_at: number; messages: number; saves: number };

const chatShaped = (row: ChatRow) => ({ id: row.id, title: row.title, project: row.project, app: row.app, startedAt: row.started_at,
  lastAt: row.last_at, messages: row.messages, savedByAi: row.saves > 0 });

export type Chat = ReturnType<typeof chatShaped>;

const CHAT = `SELECT c.id, COALESCE((SELECT s.title FROM relay_chat_saves s WHERE s.chat_id = c.id ORDER BY s.created_at DESC, s.id DESC LIMIT 1),
  NULLIF(c.title, ''), 'A chat with no title') AS title, c.project, c.app, c.started_at, c.last_at, c.message_count AS messages,
  (SELECT COUNT(*) FROM relay_chat_saves s WHERE s.chat_id = c.id) AS saves FROM relay_chats c`;

/** A word in any message or save of the chat. */
const CHAT_WORD = `(EXISTS (SELECT 1 FROM relay_chat_messages m WHERE m.chat_id = c.id AND m.text LIKE ?1 ESCAPE '\\')
  OR EXISTS (SELECT 1 FROM relay_chat_saves s WHERE s.chat_id = c.id AND (s.title LIKE ?1 ESCAPE '\\' OR s.text LIKE ?1 ESCAPE '\\')))`;

export type ChatFilter = { before?: number; beforeId?: string; after?: number; words?: string[]; limit: number };

/** A page of chats, newest first by their last message, from `after` up to `before`, holding every word in `words`. */
export async function chatPage(db: Db, filter: ChatFilter) {
  const { before = Number.MAX_SAFE_INTEGER, beforeId = "", after = 0, words = [], limit } = filter;
  // Each word binds once and is read by number in its own clause, so one word reaches every table it searches.
  const where = ["(c.last_at < ?1 OR (c.last_at = ?1 AND c.id < ?2))", "c.last_at >= ?3",
    ...words.map((_, index) => CHAT_WORD.replaceAll("?1", `?${index + 5}`))];
  const { results } = await db.prepare(`${CHAT} WHERE ${where.join(" AND ")} ORDER BY c.last_at DESC, c.id DESC LIMIT ?4`)
    .bind(before, beforeId, after, limit + 1, ...words.map(like)).all<ChatRow>();
  const page = results.slice(0, limit);
  const last = results.length > limit ? page.at(-1)! : null;
  return { chats: page.map(chatShaped), next: last?.last_at ?? null, nextId: last?.id ?? null };
}

export type ChatSave = { id: string; title: string; text: string; createdAt: number };

/** One chat and its saves, newest first, or null. */
export async function chatById(db: Db, id: string): Promise<(Chat & { saves: ChatSave[] }) | null> {
  const [row, { results }] = await Promise.all([db.prepare(`${CHAT} WHERE c.id = ?`).bind(id).first<ChatRow>(),
    db.prepare(`SELECT id, title, text, created_at AS createdAt FROM relay_chat_saves WHERE chat_id = ? ORDER BY created_at DESC, id DESC`)
      .bind(id).all<ChatSave>()]);
  return row && { ...chatShaped(row), saves: results };
}

export type ChatMessage = { seq: number; role: "you" | "ai" | "step"; text: string; at: number };

/** A part's text stops growing past this many characters, so a part of long messages stays a few megabytes at most. */
const PART_CHARACTERS = 600_000;

/** Up to `limit` messages after the message at `after`, in order, and the last one's place to read on from. */
export async function chatMessages(db: Db, id: string, after: number, limit: number) {
  const { results } = await db.prepare("SELECT seq, role, text, at FROM relay_chat_messages WHERE chat_id = ? AND seq > ? ORDER BY seq LIMIT ?")
    .bind(id, after, limit + 1).all<ChatMessage>();
  const part: ChatMessage[] = [];
  let size = 0;
  for (const message of results.slice(0, limit)) {
    if (part.length && size + message.text.length > PART_CHARACTERS) break;
    part.push(message);
    size += message.text.length;
  }
  return { messages: part, next: part.length < results.length ? part.at(-1)!.seq : null };
}

/** Up to `limit` messages of one chat that hold any of the words, in order; give at least one word. */
export async function chatLines(db: Db, id: string, words: string[], limit: number): Promise<ChatMessage[]> {
  const { results } = await db.prepare(`SELECT seq, role, text, at FROM relay_chat_messages WHERE chat_id = ? AND
    (${words.map(() => "text LIKE ? ESCAPE '\\'").join(" OR ")}) ORDER BY seq LIMIT ?`).bind(id, ...words.map(like), limit).all<ChatMessage>();
  return results;
}

// Photos: each row's time, place and size. Its file's name stays here, for read_photo to open it through space.ts.
type PhotoRow = { id: string; taken_at: number; lat: number | null; lon: number | null; width: number; height: number; file_key: string };

const photoShaped = (row: PhotoRow) => ({ id: row.id, takenAt: row.taken_at, lat: row.lat, lon: row.lon, width: row.width, height: row.height });

export type Photo = ReturnType<typeof photoShaped>;
/** A point and a distance from it, in kilometres. */
export type Near = { lat: number; lon: number; km: number };

const EARTH_KM = 6371;
const radians = (degrees: number) => degrees * Math.PI / 180;

/** The great-circle distance between two points, in kilometres. */
export function distanceKm(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const [dLat, dLon] = [radians(b.lat - a.lat), radians(b.lon - a.lon)];
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(radians(a.lat)) * Math.cos(radians(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** The SQL and values for a box around the point that holds every place within `km` of it, across the date line too. */
function box({ lat, lon, km }: Near): { sql: string; values: number[] } {
  const dLat = km / 111.2;
  const south = Math.max(-90, lat - dLat);
  const north = Math.min(90, lat + dLat);
  const dLon = km / (111.2 * Math.cos(radians(Math.max(Math.abs(south), Math.abs(north)))));
  const around = "p.lat BETWEEN ? AND ?";
  // Near a pole, or far enough, the box goes all the way round.
  if (!Number.isFinite(dLon) || dLon >= 180) return { sql: around, values: [south, north] };
  const [west, east] = [lon - dLon, lon + dLon];
  if (west < -180) return { sql: `${around} AND (p.lon >= ? OR p.lon <= ?)`, values: [south, north, west + 360, east] };
  if (east > 180) return { sql: `${around} AND (p.lon >= ? OR p.lon <= ?)`, values: [south, north, west, east - 360] };
  return { sql: `${around} AND p.lon BETWEEN ? AND ?`, values: [south, north, west, east] };
}

export type PhotoFilter = { before?: number; beforeId?: string; after?: number; near?: Near; limit: number };

/** A page of photos, newest first, from `after` up to `before`; with `near`, only those taken within its distance. The
 *  cursor is the page's last row, so a page that `near` thinned still reads on from the right place. */
export async function photoPage(db: Db, filter: PhotoFilter) {
  const { before = Number.MAX_SAFE_INTEGER, beforeId = "", after = 0, near, limit } = filter;
  const place = near && box(near);
  const where = ["(p.taken_at < ? OR (p.taken_at = ? AND p.id < ?))", "p.taken_at >= ?", ...place ? [place.sql] : []];
  const { results } = await db.prepare(`SELECT p.id, p.taken_at, p.lat, p.lon, p.width, p.height FROM relay_photos p
      WHERE ${where.join(" AND ")} ORDER BY p.taken_at DESC, p.id DESC LIMIT ?`)
    .bind(before, before, beforeId, after, ...place ? place.values : [], limit + 1).all<PhotoRow>();
  const page = results.slice(0, limit);
  const last = results.length > limit ? page.at(-1)! : null;
  const kept = near ? page.filter(row => distanceKm(near, { lat: row.lat!, lon: row.lon! }) <= near.km) : page;
  return { photos: kept.map(photoShaped), next: last?.taken_at ?? null, nextId: last?.id ?? null };
}

/** One photo and its file's name, or null. */
export async function photoById(db: Db, id: string): Promise<(Photo & { file: string }) | null> {
  const row = await db.prepare("SELECT id, taken_at, lat, lon, width, height, file_key FROM relay_photos WHERE id = ?").bind(id).first<PhotoRow>();
  return row && { ...photoShaped(row), file: row.file_key };
}
