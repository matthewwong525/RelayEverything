// Relay's reads, shared by the app's routes and the AI connector (app/worker/relay-mcp/): each is capped, and each is
// SELECT only, so the connector can read every note and change none. A test fails on any other statement here.
import { MINUTE, type Db } from "./store.ts";

/** Every health type a phone sends, each in one unit: the one list POST health, the webhooks and the connector take. */
export const HEALTH_TYPES = ["steps", "heart_rate", "sleep", "workout", "weight", "resting_heart_rate", "hrv_sdnn", "hrv_rmssd",
  "blood_oxygen", "blood_pressure_systolic", "blood_pressure_diastolic", "cycle_flow", "mindful", "water"] as const;
export type HealthType = (typeof HEALTH_TYPES)[number];
/** A span from its first millisecond to the first one after it. */
export type Span = [number, number];

// A note has no place: relay_notes keeps its place columns empty (0017_note_places.sql); a reader finds places by time.
type Row = { id: string; source: "ring" | "typed"; text: string; recorded_at: number; device: string; audio: number; files: string };

/** A note's file: `ready` once the phone has sent its bytes, which GET attachment then opens. */
export type NoteFile = { id: string; name: string; type: string; size: number; ready: boolean };

const shaped = (row: Row) => ({ id: row.id, source: row.source, text: row.text, recordedAt: row.recorded_at, device: row.device,
  audio: row.audio === 1,
  attachments: (JSON.parse(row.files) as (Omit<NoteFile, "ready"> & { ready: number })[]).map(file => ({ ...file, ready: file.ready === 1 })) });

export type Note = ReturnType<typeof shaped>;

const FILES = `(SELECT json_group_array(json_object('id', a.id, 'name', a.name, 'type', a.content_type, 'size', a.size,
  'ready', a.file_key IS NOT NULL)) FROM (SELECT * FROM relay_attachments WHERE note_id = n.id ORDER BY rowid) a) AS files`;
const COLUMNS = `n.id, n.source, n.text, n.recorded_at, d.name AS device, n.audio_key IS NOT NULL AS audio,
  ${FILES}`;
const NOTE = `SELECT ${COLUMNS} FROM relay_notes n JOIN relay_devices d ON d.id = n.device_id`;

export type NoteFilter = { before?: number; beforeId?: string; after?: number; source?: "ring" | "typed"; words?: string[]; tag?: string; limit: number };

/** LIKE's own characters, escaped, so a word matches as typed. */
const escaped = (word: string) => word.replace(/[\\%_]/g, "\\$&");
const like = (word: string) => `%${escaped(word)}%`;

/** A topic and its parts: `bike` finds `bike` and `bike/charging`, never `biker`. Bind tagValues(tag) after it. */
export const tagged = (table: "relay_memory_tags" | "relay_note_tags", own: "fact_id" | "note_id", key: string) =>
  `EXISTS (SELECT 1 FROM ${table} t WHERE t.${own} = ${key} AND (t.tag = ? OR t.tag LIKE ? ESCAPE '\\'))`;
export const tagValues = (tag: string) => [tag, `${escaped(tag)}/%`];

/** A page of notes, newest first, from `after` up to `before`, holding every word in `words` in any case. */
export async function notePage(db: Db, filter: NoteFilter) {
  const { before = Number.MAX_SAFE_INTEGER, beforeId = "", after = 0, source, words = [], tag, limit } = filter;
  const where = ["(n.recorded_at < ? OR (n.recorded_at = ? AND n.id < ?))", "n.recorded_at >= ?",
    ...source ? ["n.source = ?"] : [], ...words.map(() => "n.text LIKE ? ESCAPE '\\'"),
    ...tag === undefined ? [] : [tagged("relay_note_tags", "note_id", "n.id")]];
  const { results } = await db.prepare(`${NOTE} WHERE ${where.join(" AND ")} ORDER BY n.recorded_at DESC, n.id DESC LIMIT ?`)
    .bind(before, before, beforeId, after, ...source ? [source] : [], ...words.map(like), ...tag === undefined ? [] : tagValues(tag), limit + 1).all<Row>();
  const page = results.slice(0, limit);
  // Two notes can share a time, so a page ends at a time and an id: the next page starts just after both.
  const last = results.length > limit ? page.at(-1)! : null;
  return { notes: page.map(shaped), next: last?.recorded_at ?? null, nextId: last?.id ?? null };
}

export async function noteById(db: Db, id: string): Promise<Note | null> {
  const row = await db.prepare(`${NOTE} WHERE n.id = ?`).bind(id).first<Row>();
  return row && shaped(row);
}

type SyncRow = Row & { seq: number; deleted: number; note_id: string; deleted_client_id: string | null; client_id: string | null;
  edited_at: number | null; device_id: string };
// A deleted note's row has no note to join: it reads as its ids alone.
const SYNCED = `SELECT c.seq, c.deleted, c.note_id, c.client_id AS deleted_client_id, n.client_id, n.edited_at, n.device_id, ${COLUMNS}
  FROM relay_note_changes c
  LEFT JOIN relay_notes n ON n.id = c.note_id LEFT JOIN relay_devices d ON d.id = n.device_id`;

/** The timeline's note, and what a phone needs to sync it: its own id, whether it sent it, and the last change. */
const synced = (row: SyncRow, deviceId: string | null) =>
  ({ ...shaped(row), clientId: row.client_id, mine: row.device_id === deviceId, editedAt: row.edited_at });

/** The notes changed after change number `since`, oldest change first; `next` is the page's last number. With
 *  `deleted`, a deleted note comes as `{ id, clientId, deleted: true }`; without it, as an older phone asks, none. */
export async function noteChanges(db: Db, since: number, limit: number, deviceId: string | null, deleted = false) {
  const { results } = await db.prepare(`${SYNCED} WHERE c.seq > ? AND (c.deleted = 0 OR ?) ORDER BY c.seq LIMIT ?`)
    .bind(since, deleted ? 1 : 0, limit + 1).all<SyncRow>();
  const page = results.slice(0, limit);
  return { notes: page.map(row => row.deleted ? { id: row.note_id, clientId: row.deleted_client_id, deleted: true as const } : synced(row, deviceId)),
    next: page.at(-1)?.seq ?? since, more: results.length > limit };
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

/** At most this many stays and trips in one day's summary. */
const DAY_PLACES = 400;

/** The range's stays and trips, read once, and whether a point lies in one: a point no stay or trip covers reads as
 *  before stays, as on an old day or a phone that sends only points. Binds `from` as ?1 and `to` as ?2. */
const COVERS = "WITH c AS MATERIALIZED (SELECT start_at, end_at FROM relay_stays WHERE start_at < ?2 AND end_at >= ?1)";
const COVERED = "EXISTS (SELECT 1 FROM c WHERE c.start_at <= l.at AND c.end_at >= l.at)";

/** A day's places, one row per stay, and its trips. Points no stay or trip covers give each place once, as before. */
async function dayPlaces(db: Db, from: number, to: number) {
  const [{ results }, found] = await Promise.all([db.prepare(`${COVERS} SELECT ${NAME} AS name, AVG(lat) AS lat, AVG(lon) AS lon,
    MIN(at) AS "from", MAX(at) AS "to" FROM relay_locations l WHERE at >= ?1 AND at < ?2 AND NOT ${COVERED} GROUP BY 1 ORDER BY 4`)
    .bind(from, to).all<{ name: string; lat: number; lon: number; from: number; to: number }>(), staysIn(db, from, to, DAY_PLACES)]);
  const stays = found.visits.map(({ id, name, lat, lon, arrived, left, address, event, ongoing }) =>
    ({ id, name, lat, lon, from: arrived, to: left, ...address && { address }, ...event && { event }, ...ongoing && { ongoing } }));
  return { places: [...results, ...stays].sort((a, b) => a.from - b.from), trips: found.trips };
}

/** At most this many nights, and workouts, in one day's summary. */
const DAY_NIGHTS = 10;
const DAY_WORKOUTS = 50;

/** One day: how many notes, the health totals, the nights that ended in it and its workouts, the places (one row per
 *  stay), its trips, and the calendar's events. */
export async function daySummary(db: Db, from: number, to: number) {
  const spans: Span[] = [[from, to]];
  const [notes, [steps], [sleep], [heart], [workouts], more, bloodPressure, places, events, nights, items] = await Promise.all([
    db.prepare("SELECT COUNT(*) AS count FROM relay_notes WHERE recorded_at >= ? AND recorded_at < ?").bind(from, to).first<{ count: number }>(),
    healthBuckets(db, "steps", spans), healthBuckets(db, "sleep", spans), healthBuckets(db, "heart_rate", spans),
    healthBuckets(db, "workout", spans), dayHealth(db, spans), pressures(db, from, to),
    dayPlaces(db, from, to),
    eventPage(db, { from, to, limit: DAY_EVENTS }),
    nightPage(db, { from, to, limit: DAY_NIGHTS }, false), workoutPage(db, { from, to, limit: DAY_WORKOUTS }),
  ]);
  return { notes: notes!.count, steps: steps.total!, sleepMinutes: sleep.total!,
    heartRate: heart.min === null ? null : { min: heart.min!, max: heart.max!, average: heart.average! },
    nights: nights.nights.reverse(),
    workouts: { count: workouts.count!, minutes: workouts.minutes!, items: items.workouts.reverse() },
    ...more, ...bloodPressure.length > 0 && { bloodPressure },
    ...places,
    events: events.events.map(({ title, start, end, allDay, people }) => ({ title, start, end, allDay, people: people.flatMap(person => person.name ?? []) })) };
}

/** Rows read at a time, newest first, until enough are kept after duplicates merge. */
const PAGE = 200;

/** Up to `limit` rows, newest first, read PAGE at a time: a row that `same` matches with the last one kept merges into
 *  it, and replaces it when `better`. `more` says a row past the page was kept. */
async function newest<Row>(read: (offset: number) => Promise<Row[]>, limit: number, same: (row: Row, kept: Row) => boolean,
  better: (row: Row, kept: Row) => boolean) {
  const kept: Row[] = [];
  for (let offset = 0, more = true; more && kept.length <= limit; offset += PAGE) {
    const rows = await read(offset);
    more = rows.length === PAGE;
    for (const row of rows) {
      const last = kept.at(-1);
      if (last && same(row, last)) {
        if (better(row, last)) kept[kept.length - 1] = row;
      } else if (kept.push(row) > limit) break;
    }
  }
  return { rows: kept.slice(0, limit), more: kept.length > limit };
}

/** A page of a newest-first read: from `from` up to `to`, and before `before`, the last page's cursor. */
type HealthFilter = { from: number; to: number; before?: number; limit: number };

type NightRow = { id: number; source: string; start_at: number; end_at: number; asleep_at: number | null; woke_at: number | null;
  asleep: number; core: number; deep: number; rem: number; awake: number; stages: string; device: string };
type SleepStep = { stage: string; start: number; end: number };

const nightShaped = (row: NightRow) => ({ start: row.start_at, end: row.end_at, asleepAt: row.asleep_at, wokeAt: row.woke_at,
  minutes: { asleep: Math.round(row.asleep), core: Math.round(row.core), deep: Math.round(row.deep), rem: Math.round(row.rem),
    awake: Math.round(row.awake) }, source: row.source, device: row.device });

/** The nights that end from `from` up to `to`, newest first, with each timeline when `stages`. Of nights that overlap,
 *  the one most asleep is kept, as a watch's over the phone's bedtime. `next`: nights that end by the last start. */
export async function nightPage(db: Db, { from, to, before = to, limit }: HealthFilter, stages: boolean) {
  const end = Math.min(to, before);
  const found = await newest(async offset => (await db.prepare(`SELECT n.id, n.source, n.start_at, n.end_at, n.asleep_at, n.woke_at,
      n.asleep, n.core, n.deep, n.rem, n.awake, n.stages, d.name AS device FROM relay_nights n JOIN relay_devices d ON d.id = n.device_id
      WHERE n.end_at >= ? AND n.end_at < ? ORDER BY n.end_at DESC, n.id DESC LIMIT ? OFFSET ?`)
    .bind(from, end, PAGE, offset).all<NightRow>()).results, limit,
  (row, kept) => row.end_at > kept.start_at, (row, kept) => row.asleep > kept.asleep);
  return { nights: found.rows.map(row => ({ ...nightShaped(row), ...stages && { stages: JSON.parse(row.stages) as SleepStep[] } })),
    next: found.more ? found.rows.at(-1)!.start_at + 1 : null };
}

type WorkoutRow = { id: number; start_at: number; end_at: number; source: string; kind: string | null; distance: number | null;
  calories: number | null; device: string };

const workoutShaped = (row: WorkoutRow) => ({ kind: row.kind, start: row.start_at, end: row.end_at,
  minutes: Math.round((row.end_at - row.start_at) / MINUTE), km: row.distance === null ? null : Math.round(row.distance / 10) / 100,
  calories: row.calories === null ? null : Math.round(row.calories), source: row.source, device: row.device });

/** The workouts that start from `from` up to `to`, newest first. One workout that two phones or sources both keep,
 *  starting within a minute, is given once, with its details when one of them has them. */
export async function workoutPage(db: Db, { from, to, before = to, limit }: HealthFilter) {
  const end = Math.min(to, before);
  const found = await newest(async offset => (await db.prepare(`SELECT h.id, h.start_at, h.end_at, h.source, h.kind, h.distance,
      h.calories, d.name AS device FROM relay_health h JOIN relay_devices d ON d.id = h.device_id
      WHERE h.type = 'workout' AND h.start_at >= ? AND h.start_at < ? ORDER BY h.start_at DESC, h.id DESC LIMIT ? OFFSET ?`)
    .bind(from, end, PAGE, offset).all<WorkoutRow>()).results, limit,
  (row, kept) => kept.start_at - row.start_at < MINUTE, (row, kept) => row.kind !== null && kept.kind === null);
  return { workouts: found.rows.map(workoutShaped), next: found.more ? found.rows.at(-1)!.start_at - MINUTE + 1 : null };
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

type Run = { name: string; lat: number; lon: number; arrived: number; left: number };
/** A stay: a time in one place. `id` only for a phone's stay; `address` and `event` only when set; `ongoing` only while
 *  the person is there. */
type Visit = { id?: number } & Run & { minutes: number; address?: string; event?: string; ongoing?: true };
/** A trip between two stays, with the names of the stays at each end when they are known. */
type Trip = { id: number; left: number; arrived: number; mode: string; km: number; minutes: number; from: string | null; to: string | null };
export type StayRow = { id: number; kind: "stay" | "trip"; start_at: number; end_at: number; ongoing: number; updated_at: number; lat: number | null;
  lon: number | null; name: string | null; address: string | null; event: string | null; mode: string | null; km: number | null };

const minutesOf = (from: number, to: number) => Math.round((to - from) / MINUTE);
/** An ongoing stay not sent for this long ended at its end: the phone stopped sending, or was turned off. */
const STALE = 360 * MINUTE;

/** Visits from points no stay or trip covers: each run of points at one place is one visit, as before stays. A
 *  covered point ends a run, so a street before and after a stay gives two visits. */
async function streetRuns(db: Db, from: number, to: number, limit: number): Promise<Visit[]> {
  const { results } = await db.prepare(`${COVERS} SELECT name, AVG(lat) AS lat, AVG(lon) AS lon, MIN(at) AS arrived,
      MAX(at) AS "left" FROM (SELECT *, SUM(moved) OVER (ORDER BY at, id) AS visit FROM
        (SELECT *, run IS NOT lag(run) OVER (ORDER BY at, id) AS moved FROM
          (SELECT id, at, lat, lon, ${NAME} AS name, IIF(${COVERED}, NULL, ${NAME}) AS run
            FROM relay_locations l WHERE at >= ?1 AND at < ?2)))
    WHERE run IS NOT NULL GROUP BY visit ORDER BY arrived LIMIT ?3`).bind(from, to, limit).all<Run>();
  return results.map(run => ({ ...run, minutes: minutesOf(run.arrived, run.left) }));
}

/** Where two phones' stays, or trips, overlap, the longer one is kept. */
function longest(rows: StayRow[]): StayRow[] {
  const kept: StayRow[] = [];
  for (const row of rows) {
    const last = kept.findLast(other => other.kind === row.kind);
    if (!last || row.start_at >= last.end_at) kept.push(row);
    else if (row.end_at - row.start_at > last.end_at - last.start_at) kept[kept.lastIndexOf(last)] = row;
  }
  return kept;
}

/** Still going on: sent as ongoing within the last 6 hours. */
export const going = (row: Pick<StayRow, "ongoing" | "end_at" | "updated_at">) => row.ongoing === 1 && Date.now() - Math.max(row.end_at, row.updated_at) < STALE;

const visitOf = (row: StayRow): Visit => ({ id: row.id, name: row.name!, lat: row.lat!, lon: row.lon!, arrived: row.start_at, left: row.end_at,
  minutes: minutesOf(row.start_at, row.end_at), ...row.address !== null && { address: row.address },
  ...row.event !== null && { event: row.event }, ...going(row) && { ongoing: true as const } });


/** The stays and trips that overlap `from` to `to`, oldest first: the first `want` stays, or all, and the trips read
 *  with them. Each trip names the stays it left and reached. */
async function staysIn(db: Db, from: number, to: number, want: number) {
  const read: StayRow[] = [];
  let rows: StayRow[] = [];
  // One stay more than wanted, as a row read later can still replace the last stay kept.
  for (let more = true; more && rows.filter(row => row.kind === "stay").length <= want;) {
    const { results } = await db.prepare(`SELECT id, kind, start_at, end_at, ongoing, updated_at, lat, lon, name, address, event, mode,
      km FROM relay_stays WHERE start_at < ? AND (end_at > ? OR start_at >= ?) ORDER BY start_at, kind, id LIMIT ? OFFSET ?`)
      .bind(to, from, from, PAGE, read.length).all<StayRow>();
    read.push(...results);
    more = results.length === PAGE;
    rows = longest(read);
  }
  const stays = rows.filter(row => row.kind === "stay");
  const trips = rows.filter(row => row.kind === "trip").map((row): Trip => ({ id: row.id, left: row.start_at, arrived: row.end_at, mode: row.mode!,
    km: row.km!, minutes: minutesOf(row.start_at, row.end_at),
    from: stays.findLast(stay => stay.end_at <= row.start_at)?.name ?? null, to: stays.find(stay => stay.start_at >= row.end_at)?.name ?? null }));
  return { visits: stays.slice(0, want).map(visitOf), trips };
}

/** Visits and trips from `from` to `to`, oldest first. Points no stay or trip covers give a visit per run of points at
 *  one place, as before stays. `next` is the first visit left out; the trips are those before it. */
export async function placeVisits(db: Db, from: number, to: number, limit: number) {
  const [old, found] = await Promise.all([streetRuns(db, from, to, limit + 1), staysIn(db, from, to, limit + 1)]);
  const visits = [...old, ...found.visits].sort((a, b) => a.arrived - b.arrived);
  const next = visits[limit]?.arrived ?? null;
  return { visits: visits.slice(0, limit), trips: found.trips.filter(trip => next === null || trip.left < next), next };
}

// Chats: each one's title is the newest save's, else the title of its first send. Neither the device nor the app's
// session id leaves here.
type ChatRow = { id: string; title: string; project: string; app: "claude-code" | "codex"; started_at: number; last_at: number; messages: number; saves: number };

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
