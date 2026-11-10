import { expect, it } from "vitest";
import { ANA, db, env, NOW } from "../../../tests/relay";
import { chatLines, daySummary, distanceKm, healthBuckets, nightPage, noteById, notePage, photoById, photoPage, placeVisits,
  workoutPage } from "./queries";
import { spaceOf, vouch } from "./space";

const HOUR = 3_600_000;
/** Ana's space, as her signed-in routes read it. */
const session = () => spaceOf(env() as never, vouch("session", ANA)).db;
const steps = (device: string, source: string, start: number, value: number) => db.sql.prepare(`INSERT INTO relay_health
  (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES (?, 'steps', ?, ?, ?, 'count', ?, 0)`)
  .run(device, start, start + HOUR / 2, value, source);
const reading = (type: string, start: number, value: number, { end = start, source = "Health Connect", device = "d-phone" } = {}) =>
  db.sql.prepare(`INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES (?, ?, ?, ?, ?, '', ?, 0)`)
    .run(device, type, start, end, value, source);
const typed = (id: string, text: string, at: number) => db.sql.prepare(`INSERT INTO relay_notes (id, device_id, source, client_id, text,
  recorded_at, created_at) VALUES (?, 'd-phone', 'typed', ?, ?, ?, 0)`).run(id, `client-${id}`, text, at);
const point = (at: number, place: string | null, lat = 43.65) => db.sql.prepare(`INSERT INTO relay_locations (device_id, at, lat, lon,
  accuracy, place, created_at) VALUES ('d-phone', ?, ?, -79.38, 10, ?, 0)`).run(at, lat, place);

it("counts each hour's steps once: the largest device, after each device's largest source", async () => {
  steps("d-phone", "Health Connect", NOW, 1000);
  steps("d-phone", "Health Connect", NOW + HOUR / 2, 500);
  steps("d-phone", "Samsung Health", NOW, 1200);
  steps("d-ipad", "iPad", NOW + HOUR, 300);
  const buckets = await healthBuckets(session(), "steps", [[NOW, NOW + HOUR], [NOW + HOUR, NOW + 2 * HOUR], [NOW + 2 * HOUR, NOW + 3 * HOUR]]);
  expect(buckets.map(bucket => bucket.total)).toEqual([1500, 300, 0]);
});

it("matches a word's % and _ as typed", async () => {
  typed("aaaaaaaa-0000-4000-8000-000000000001", "Up 100% on the pcb_v2 board", NOW);
  typed("aaaaaaaa-0000-4000-8000-000000000002", "Up 1000 on the pcbxv2 board", NOW - 1);
  const found = async (words: string[]) => (await notePage(session(), { words, limit: 10 })).notes.map(note => note.text);
  expect(await found(["100%"])).toEqual(["Up 100% on the pcb_v2 board"]);
  expect(await found(["pcb_v2"])).toEqual(["Up 100% on the pcb_v2 board"]);
  expect(await found(["BOARD", "up"])).toHaveLength(2);
  expect((await notePage(session(), { source: "ring", limit: 10 })).notes).toEqual([]);
  expect((await notePage(session(), { source: "typed", words: ["up"], limit: 10 })).notes).toHaveLength(2);
});

it("joins points at one place into one visit, and names a place with no name by where it is", async () => {
  point(NOW, "Queen St W");
  point(NOW + 10 * 60_000, "Queen St W");
  point(NOW + 20 * 60_000, null, 43.70);
  point(NOW + 30 * 60_000, "Queen St W");
  const { visits, next } = await placeVisits(session(), NOW, NOW + HOUR, 10);
  expect(visits.map(visit => [visit.name, visit.arrived, visit.left])).toEqual([["Queen St W", NOW, NOW + 10 * 60_000],
    ["43.700, -79.380", NOW + 20 * 60_000, NOW + 20 * 60_000], ["Queen St W", NOW + 30 * 60_000, NOW + 30 * 60_000]]);
  expect(next).toBeNull();
});

const MIN = 60_000;
/** A stay or a trip as the phone sent it. */
const segment = (kind: "stay" | "trip", start: number, end: number, more: Record<string, unknown> = {}) => {
  const row = { device_id: "d-phone", ongoing: 0, lat: null, lon: null, name: null, address: null, event: null, source: null, mode: null, km: null,
    updated_at: 0, ...kind === "stay" ? { lat: 43.65, lon: -79.38, source: "street" } : { mode: "driving", km: 6.2 }, ...more };
  db.sql.prepare(`INSERT INTO relay_stays (device_id, kind, start_at, end_at, ongoing, lat, lon, name, address, event, source, mode, km,
    updated_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`).run(row.device_id, kind, start, end, row.ongoing, row.lat,
    row.lon, row.name, row.address, row.event, row.source, row.mode, row.km, row.updated_at);
};
/** A made-up Saturday from the update on: home, a drive, a café you are still at. */
function saturday() {
  segment("stay", NOW - 2 * HOUR, NOW, { name: "12 Maple Street" });
  segment("trip", NOW, NOW + 15 * MIN);
  segment("stay", NOW + 15 * MIN, NOW + 25 * MIN, { name: "Corner Café", address: "Lake Drive", source: "map", ongoing: 1 });
}

it("reads stays and trips in order, each trip with the stays at its ends, and an ongoing stay as ongoing", async () => {
  saturday();
  const { visits, trips, next } = await placeVisits(session(), NOW - 3 * HOUR, NOW + HOUR, 10);
  expect(visits).toEqual([
    { name: "12 Maple Street", lat: 43.65, lon: -79.38, arrived: NOW - 2 * HOUR, left: NOW, minutes: 120 },
    { name: "Corner Café", lat: 43.65, lon: -79.38, arrived: NOW + 15 * MIN, left: NOW + 25 * MIN, minutes: 10, address: "Lake Drive", ongoing: true }]);
  expect(trips).toEqual([{ left: NOW, arrived: NOW + 15 * MIN, mode: "driving", km: 6.2, minutes: 15, from: "12 Maple Street", to: "Corner Café" }]);
  expect(next).toBeNull();
  // A range inside a stay still gets the stay.
  expect((await placeVisits(session(), NOW - HOUR, NOW - HOUR / 2, 10)).visits.map(visit => visit.name)).toEqual(["12 Maple Street"]);
});

it("pages stays from next, with each trip on the page before it, and keeps the longer of two phones' stays", async () => {
  saturday();
  segment("stay", NOW - 90 * MIN, NOW - 60 * MIN, { device_id: "d-ipad", name: "Kitchen" });
  const first = await placeVisits(session(), NOW - 3 * HOUR, NOW + HOUR, 1);
  expect(first.visits.map(visit => visit.name)).toEqual(["12 Maple Street"]);
  expect(first.next).toBe(NOW + 15 * MIN);
  expect(first.trips.map(trip => trip.left)).toEqual([NOW]);
  const second = await placeVisits(session(), first.next!, NOW + HOUR, 1);
  expect([second.visits.map(visit => visit.name), second.trips, second.next]).toEqual([["Corner Café"], [], null]);
});

it("keeps the longer of two phones' overlapping trips, and names no stay for a trip with none at that end", async () => {
  segment("stay", NOW - 2 * HOUR, NOW, { name: "12 Maple Street" });
  segment("trip", NOW - 3 * HOUR, NOW - 2 * HOUR);
  segment("trip", NOW - 150 * MIN, NOW - 30 * MIN, { device_id: "d-ipad", mode: "walking" });
  segment("trip", NOW, NOW + HOUR);
  const { visits, trips } = await placeVisits(session(), NOW - 3 * HOUR, NOW + 30 * MIN, 10);
  expect(visits.map(visit => visit.name)).toEqual(["12 Maple Street"]);
  expect(trips.map(trip => [trip.mode, trip.from, trip.to])).toEqual([["walking", null, null], ["driving", "12 Maple Street", null]]);
});

it("reads a day before the space's first stay as before: street runs, and each place once in the day's summary", async () => {
  point(NOW - 26 * HOUR, "Queen St W");
  point(NOW - 25 * HOUR, "Queen St W");
  point(NOW - 24.5 * HOUR, "Bay St");
  saturday();
  const old = await placeVisits(session(), NOW - 27 * HOUR, NOW - 24 * HOUR, 10);
  expect([old.visits.map(visit => [visit.name, visit.arrived, visit.left]), old.trips]).toEqual([
    [["Queen St W", NOW - 26 * HOUR, NOW - 25 * HOUR], ["Bay St", NOW - 24.5 * HOUR, NOW - 24.5 * HOUR]], []]);
  // Points sent beside stays, from the update on, give no second row.
  point(NOW + 20 * MIN, "Lake Drive");
  expect((await placeVisits(session(), NOW - 27 * HOUR, NOW + HOUR, 10)).visits.map(visit => visit.name))
    .toEqual(["Queen St W", "Bay St", "12 Maple Street", "Corner Café"]);
  const day = await daySummary(session(), NOW - 27 * HOUR, NOW + HOUR);
  expect(day.places).toEqual([
    { name: "Queen St W", lat: 43.65, lon: -79.38, from: NOW - 26 * HOUR, to: NOW - 25 * HOUR },
    { name: "Bay St", lat: 43.65, lon: -79.38, from: NOW - 24.5 * HOUR, to: NOW - 24.5 * HOUR },
    { name: "12 Maple Street", lat: 43.65, lon: -79.38, from: NOW - 2 * HOUR, to: NOW },
    { name: "Corner Café", lat: 43.65, lon: -79.38, from: NOW + 15 * MIN, to: NOW + 25 * MIN, address: "Lake Drive", ongoing: true }]);
  expect(day.trips).toHaveLength(1);
});

it("fills the time no stay or trip covers with street runs, as a phone on Only points sends, after the first stay too", async () => {
  saturday();
  for (const [minutes, place] of [[30, "Lake Drive"], [40, "Lake Drive"], [50, "Park Lane"], [-150, "Lake Drive"]] as const) {
    point(NOW + minutes * MIN, place);
  }
  // A point inside the café stay ends Lake Drive's run, so the street before and after it gives two visits.
  point(NOW + 20 * MIN, "Lake Drive");
  point(NOW + 10 * MIN, "Elm Road");
  const { visits, trips } = await placeVisits(session(), NOW - 3 * HOUR, NOW + HOUR, 10);
  expect(visits.map(visit => [visit.name, visit.arrived, visit.left])).toEqual([["Lake Drive", NOW - 150 * MIN, NOW - 150 * MIN],
    ["12 Maple Street", NOW - 2 * HOUR, NOW], ["Corner Café", NOW + 15 * MIN, NOW + 25 * MIN],
    ["Lake Drive", NOW + 30 * MIN, NOW + 40 * MIN], ["Park Lane", NOW + 50 * MIN, NOW + 50 * MIN]]);
  expect(trips).toHaveLength(1);
  const day = await daySummary(session(), NOW - 3 * HOUR, NOW + HOUR);
  expect(day.places.map(place => [place.name, place.from, place.to])).toEqual([["Lake Drive", NOW - 150 * MIN, NOW + 40 * MIN],
    ["12 Maple Street", NOW - 2 * HOUR, NOW], ["Corner Café", NOW + 15 * MIN, NOW + 25 * MIN], ["Park Lane", NOW + 50 * MIN, NOW + 50 * MIN]]);
});

it("reads an ongoing stay as ended when its phone has not sent it for 6 hours", async () => {
  segment("stay", NOW - 9 * HOUR, NOW - 7 * HOUR, { name: "Gone quiet", ongoing: 1 });
  segment("stay", NOW - 6.5 * HOUR, NOW - 6.2 * HOUR, { name: "Sent lately", ongoing: 1, updated_at: NOW - HOUR, device_id: "d-ipad" });
  segment("stay", NOW - 5 * HOUR, NOW - HOUR, { name: "Still there", ongoing: 1, device_id: "d-lost" });
  const { visits } = await placeVisits(session(), NOW - 10 * HOUR, NOW, 10);
  expect(visits.map(visit => [visit.name, visit.left, visit.ongoing])).toEqual([["Gone quiet", NOW - 7 * HOUR, undefined],
    ["Sent lately", NOW - 6.2 * HOUR, true], ["Still there", NOW - HOUR, true]]);
});

it("pages on past the rows three phones' overlapping stays take, so no later visit is lost", async () => {
  for (let i = 0; i < 120; i++) {
    for (const device_id of ["d-phone", "d-ipad", "d-lost"]) {
      segment("stay", NOW + i * HOUR, NOW + i * HOUR + 40 * MIN, { device_id, name: `Stay ${i}` });
      segment("trip", NOW + i * HOUR + 40 * MIN, NOW + (i + 1) * HOUR, { device_id });
    }
  }
  const first = await placeVisits(session(), NOW, NOW + 200 * HOUR, 100);
  expect([first.visits.length, first.visits.at(-1)!.name, first.next, first.trips.length]).toEqual([100, "Stay 99", NOW + 100 * HOUR, 100]);
  const second = await placeVisits(session(), first.next!, NOW + 200 * HOUR, 100);
  expect([second.visits.length, second.visits[0].name, second.next]).toEqual([20, "Stay 100", null]);
});

it("reads one note by its id, and null for an id it lacks", async () => {
  typed("aaaaaaaa-0000-4000-8000-000000000001", "Order more switches", NOW);
  expect((await noteById(session(), "aaaaaaaa-0000-4000-8000-000000000001"))?.text).toBe("Order more switches");
  expect(await noteById(session(), "aaaaaaaa-0000-4000-8000-000000000009")).toBeNull();
});

it("finds a chat's messages that hold any of the words, in order", async () => {
  db.sql.exec(`INSERT INTO relay_chats (id, device_id, session_id, app, project, title, started_at, last_at, message_count, created_at)
    VALUES ('c1', 'd-laptop', 'session-0001', 'claude-code', 'relay-ring', '', 0, 0, 3, 0)`);
  const said = db.sql.prepare("INSERT INTO relay_chat_messages (chat_id, seq, role, text, at) VALUES ('c1', ?, 'you', ?, 0)");
  ["Pick a 100% steel stiffener", "Glue it", "Steel is fine"].forEach((text, seq) => said.run(seq, text));
  expect((await chatLines(session(), "c1", ["steel", "glue"], 2)).map(line => line.seq)).toEqual([0, 1]);
  expect((await chatLines(session(), "c1", ["100%"], 10)).map(line => line.seq)).toEqual([0]);
});

const photo = (id: string, at: number, lat: number | null, lon: number | null) => db.sql.prepare(`INSERT INTO relay_photos (id, device_id,
  client_id, taken_at, lat, lon, width, height, bytes, file_key, created_at) VALUES (?, 'd-phone', ?, ?, ?, ?, 1600, 1200, 1000, ?, 0)`)
  .run(id, `client-${id}`, at, lat, lon, `people/${ANA}/photos/${id}`);
const P = (n: number) => `pppppppp-0000-4000-8000-00000000000${n}`;

it("pages photos newest first by time and id, with two photos at one time on either side of a page", async () => {
  photo(P(1), NOW, 38.71, -9.14);
  photo(P(2), NOW, 38.71, -9.14);
  photo(P(3), NOW - HOUR, null, null);
  photo(P(4), NOW - 2 * HOUR, 43.65, -79.38);
  const first = await photoPage(session(), { limit: 1 });
  expect([first.photos.map(item => item.id), first.next, first.nextId]).toEqual([[P(2)], NOW, P(2)]);
  const second = await photoPage(session(), { before: first.next!, beforeId: first.nextId!, limit: 2 });
  expect([second.photos.map(item => item.id), second.nextId]).toEqual([[P(1), P(3)], P(3)]);
  expect((await photoPage(session(), { before: second.next!, beforeId: second.nextId!, limit: 2 })).photos.map(item => item.id)).toEqual([P(4)]);
  expect((await photoPage(session(), { after: NOW - HOUR, before: NOW, limit: 10 })).photos.map(item => item.id)).toEqual([P(3)]);
  expect(await photoById(session(), P(3))).toEqual({ id: P(3), takenAt: NOW - HOUR, lat: null, lon: null, width: 1600, height: 1200,
    file: `people/${ANA}/photos/${P(3)}` });
  expect(await photoById(session(), P(9))).toBeNull();
});

it("finds photos near a place: inside the distance, not just the box, never one with no place, across the date line", async () => {
  photo(P(1), NOW, 38.7139, -9.1394);
  // Sintra is about 25 km from Lisbon; Porto about 275 km.
  photo(P(2), NOW - 4, 38.8029, -9.3817);
  photo(P(3), NOW - 2, 41.1579, -8.6291);
  photo(P(4), NOW - 3, null, null);
  // Each corner of a 30 km box is about 42 km off: in the box, not in the distance.
  photo(P(5), NOW - 1, 38.7139 + 0.26, -9.1394 + 0.34);
  photo(P(6), NOW - 5, -16.5, 179.9);
  photo(P(7), NOW - 6, -16.5, -179.9);
  const near = async (lat: number, lon: number, km: number, limit = 10) =>
    (await photoPage(session(), { near: { lat, lon, km }, limit })).photos.map(item => item.id);
  expect(await near(38.7139, -9.1394, 5)).toEqual([P(1)]);
  expect(await near(38.7139, -9.1394, 30)).toEqual([P(1), P(2)]);
  expect(await near(38.7139, -9.1394, 300)).toEqual([P(1), P(5), P(3), P(2)]);
  expect(await near(-16.5, 180, 30)).toEqual([P(6), P(7)]);
  expect(await near(-16.5, -180, 30)).toEqual([P(6), P(7)]);
  // Near a pole the box goes all the way round.
  photo(P(8), NOW - 7, 89.95, 120);
  expect(await near(89.95, -60, 20)).toEqual([P(8)]);
  // A page thinned by the distance still reads on from its last row.
  const thinned = await photoPage(session(), { near: { lat: 38.7139, lon: -9.1394, km: 30 }, limit: 2 });
  expect([thinned.photos.map(item => item.id), thinned.nextId]).toEqual([[P(1)], P(5)]);
  expect((await photoPage(session(), { near: { lat: 38.7139, lon: -9.1394, km: 30 }, before: thinned.next!, beforeId: thinned.nextId!, limit: 2 }))
    .photos.map(item => item.id)).toEqual([P(2)]);
  expect(Math.round(distanceKm({ lat: 38.7139, lon: -9.1394 }, { lat: 41.1579, lon: -8.6291 }))).toBe(275);
});

it("sums the new health types: latest weight, each blood pressure reading, highest flow, and the largest source's water and mindful", async () => {
  reading("weight", NOW, 72.1);
  reading("weight", NOW + 2 * HOUR, 71.6);
  reading("blood_pressure_systolic", NOW, 121);
  reading("blood_pressure_diastolic", NOW, 79);
  reading("blood_pressure_systolic", NOW + HOUR, 117);
  reading("blood_pressure_diastolic", NOW + HOUR, 75);
  reading("cycle_flow", NOW, 1);
  reading("cycle_flow", NOW + HOUR, 3);
  reading("water", NOW, 250);
  reading("water", NOW + HOUR, 500);
  reading("water", NOW, 600, { source: "Water app" });
  reading("mindful", NOW, 10, { end: NOW + 10 * 60_000, source: "Health" });
  reading("mindful", NOW + HOUR, 5, { end: NOW + HOUR + 5 * 60_000, source: "Health" });
  reading("mindful", NOW, 12, { end: NOW + 12 * 60_000, source: "Calm" });
  reading("resting_heart_rate", NOW, 55);
  reading("resting_heart_rate", NOW + HOUR, 58);
  reading("hrv_sdnn", NOW, 41);
  reading("hrv_rmssd", NOW, 33, { device: "d-ipad" });
  reading("blood_oxygen", NOW, 95);
  reading("blood_oxygen", NOW + HOUR, 98);
  db.sql.exec(`INSERT INTO relay_calendar_events (device_id, event_key, calendar, title, start_at, end_at, people, updated_at, created_at)
    VALUES ('d-phone', 'w:1:1', 'Work', 'Stand-up', ${NOW}, ${NOW + HOUR / 4}, '[{"email":"sam@example.com"},{"name":"Ana"}]', 0, 0)`);
  const day = await daySummary(session(), NOW - HOUR, NOW + 23 * HOUR);
  expect(day).toMatchObject({ weightKg: 71.6, restingHeartRate: 56.5, hrvSdnn: 41, hrvRmssd: 33, bloodOxygen: { min: 95, average: 96.5 },
    cycleFlow: 3, waterMl: 750, mindfulMinutes: 15, events: [{ title: "Stand-up", people: ["Ana"] }],
    bloodPressure: [{ at: NOW, upper: 121, lower: 79 }, { at: NOW + HOUR, upper: 117, lower: 75 }] });
  const empty = await daySummary(session(), NOW - 48 * HOUR, NOW - 24 * HOUR);
  expect(Object.keys(empty).sort()).toEqual(["events", "heartRate", "nights", "notes", "places", "sleepMinutes", "steps", "trips", "workouts"]);
  expect((await healthBuckets(session(), "cycle_flow", [[NOW, NOW + HOUR], [NOW + HOUR, NOW + 2 * HOUR], [NOW + 2 * HOUR, NOW + 3 * HOUR]]))
    .map(bucket => bucket.flow)).toEqual([1, 3, null]);
});

const night = (device: string, source: string, start: number, end: number, asleep: number) => db.sql.prepare(`INSERT INTO relay_nights
  (device_id, source, start_at, end_at, asleep, core, deep, rem, awake, updated_at, created_at) VALUES (?, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0)`)
  .run(device, source, start, end, asleep);
const workout = (device: string, start: number, kind: string | null, distance: number | null = null) => db.sql.prepare(`INSERT INTO
  relay_health (device_id, type, start_at, end_at, value, unit, source, kind, distance, created_at) VALUES (?, 'workout', ?, ?, 30, 'min',
  'Health', ?, ?, 0)`).run(device, start, start + HOUR / 2, kind, distance);

it("pages nights newest first, keeping the night with the most sleep of those that overlap, past a page of overlaps", async () => {
  for (let i = 0; i < 150; i++) {
    night("d-phone", "Watch", NOW + i * 24 * HOUR, NOW + i * 24 * HOUR + 8 * HOUR, 400 + i);
    night("d-phone", "Bedtime", NOW + i * 24 * HOUR + HOUR, NOW + i * 24 * HOUR + 8 * HOUR, 0);
  }
  const first = await nightPage(session(), { from: NOW, to: NOW + 200 * 24 * HOUR, limit: 120 }, false);
  expect([first.nights.length, first.nights[0].minutes.asleep, first.nights.at(-1)!.minutes.asleep]).toEqual([120, 549, 430]);
  expect(first.nights.every(item => item.source === "Watch")).toBe(true);
  const second = await nightPage(session(), { from: NOW, to: NOW + 200 * 24 * HOUR, before: first.next!, limit: 120 }, false);
  expect([second.nights.length, second.nights[0].minutes.asleep, second.next]).toEqual([30, 429, null]);
});

it("gives a workout two phones keep once, with its details, and pages on without losing one", async () => {
  workout("d-phone", NOW, null);
  workout("d-ipad", NOW + 30_000, "running", 5123);
  workout("d-ipad", NOW + 2 * HOUR + 10_000, "yoga");
  workout("d-phone", NOW + 2 * HOUR, "yoga");
  workout("d-phone", NOW + 4 * HOUR, "walking");
  const all = await workoutPage(session(), { from: NOW, to: NOW + 24 * HOUR, limit: 10 });
  expect(all.workouts.map(({ kind, km, minutes }) => [kind, km, minutes])).toEqual([["walking", null, 30], ["yoga", null, 30], ["running", 5.12, 30]]);
  const first = await workoutPage(session(), { from: NOW, to: NOW + 24 * HOUR, limit: 2 });
  const rest = await workoutPage(session(), { from: NOW, to: NOW + 24 * HOUR, before: first.next!, limit: 2 });
  expect([...first.workouts, ...rest.workouts].map(item => item.kind)).toEqual(["walking", "yoga", "running"]);
  expect(rest.next).toBeNull();
  expect((await daySummary(session(), NOW - HOUR, NOW + 23 * HOUR)).workouts.items.map(item => item.kind)).toEqual(["running", "yoga", "walking"]);
});
