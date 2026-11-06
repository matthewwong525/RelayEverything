import { expect, it } from "vitest";
import { ANA, db, env, NOW } from "../../../tests/relay";
import { chatLines, healthBuckets, noteById, notePage, placeVisits } from "./queries";
import { spaceOf, vouch } from "./space";

const HOUR = 3_600_000;
/** Ana's space, as her signed-in routes read it. */
const session = () => spaceOf(env() as never, vouch("session", ANA)).db;
const steps = (device: string, source: string, start: number, value: number) => db.sql.prepare(`INSERT INTO relay_health
  (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES (?, 'steps', ?, ?, ?, 'count', ?, 0)`)
  .run(device, start, start + HOUR / 2, value, source);
const typed = (id: string, text: string, at: number) => db.sql.prepare(`INSERT INTO relay_notes (id, device_id, source, client_id, text,
  recorded_at, created_at) VALUES (?, 'd-phone', 'typed', ?, ?, ?, 0)`).run(id, `client-${id}`, text, at);
const point = (at: number, place: string | null, lat = 43.65) => db.sql.prepare(`INSERT INTO relay_locations (device_id, at, lat, lon,
  accuracy, place, created_at) VALUES ('d-phone', ?, ?, -79.38, 10, ?, 0)`).run(at, lat, place);

it("counts each hour's steps once: the largest device, after each device's largest source", async () => {
  steps("d-phone", "Health Connect", NOW, 1000);
  steps("d-phone", "Health Connect", NOW + HOUR / 2, 500);
  steps("d-phone", "Samsung Health", NOW, 1200);
  steps("d-pebble", "Pebble", NOW + HOUR, 300);
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
