import { expect, it } from "vitest";
import { ANA, db, env, NOW } from "../../../tests/relay";
import { chatLines, distanceKm, healthBuckets, noteById, notePage, photoById, photoPage, placeVisits } from "./queries";
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
