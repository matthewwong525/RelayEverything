import { expect, it } from "vitest";
import { ANA, db, env, NOW } from "../../../tests/relay";
import { chatLines, daySummary, healthBuckets, noteById, notePage, placeVisits } from "./queries";
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
  expect(Object.keys(empty).sort()).toEqual(["events", "heartRate", "notes", "places", "sleepMinutes", "steps", "workouts"]);
  expect((await healthBuckets(session(), "cycle_flow", [[NOW, NOW + HOUR], [NOW + HOUR, NOW + 2 * HOUR], [NOW + 2 * HOUR, NOW + 3 * HOUR]]))
    .map(bucket => bucket.flow)).toEqual([1, 3, null]);
});
