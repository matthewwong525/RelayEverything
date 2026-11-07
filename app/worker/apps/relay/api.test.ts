import { expect, it } from "vitest";
import { handleApp } from "../index";
import { hashToken } from "./people";
import { spaceOf, vouch } from "./space";
import { ANA, call, checker, db, directoryDb, env, laptop, lost, makeKey, matthew, NOW, ipad, phone, queue, request, rows,
  type Who } from "../../../tests/relay";

const MINUTE = 60_000;
const typed = (clientId: string, more: Record<string, unknown> = {}) => ({ clientId, text: "Order more TL3312 switches", createdAt: NOW - 5 * MINUTE, ...more });
const sample = (type: string, start: number, end: number, value: number, more: Record<string, unknown> = {}) =>
  ({ type, start, end, value, unit: type === "heart_rate" ? "bpm" : type === "steps" ? "count" : "minutes", source: "Health Connect", ...more });
const point = (at: number, more: Record<string, unknown> = {}) => ({ at, lat: 43.6487, lon: -79.3962, accuracy: 15, place: "Queen St W", ...more });
const ringNote = (id: string, recordedAt: number) => db.sql.prepare(`INSERT INTO relay_notes (id, device_id, source, delivery_id, text, audio_key,
  recorded_at, created_at) VALUES (?, 'd-ipad', 'ring', ?, 'Ring note', ?, ?, 0)`).run(id, `delivery-${id}`, `people/${ANA}/${id}`, recordedAt);
const RING = "aaaaaaaa-0000-4000-8000-000000000001";
/** Seals a recording into Ana's folder, as a stored ring note keeps one. */
const seal = (id: string, bytes: number[]) => spaceOf(env() as never, vouch("session", ANA)).files.put(id, new Uint8Array(bytes).buffer);
/** The audio route as `who` plays it, with a Range header when one is given. */
const play = (who: Who, id: string, range?: string) => handleApp(request(who, "GET", `https://relay.example.com/apps/relay/api/audio?id=${id}`,
  range ? { headers: { Range: range } } : {}), env(), null);

it("has no Pebble address: a live phone key posting a signed ring note there gets not found and stores nothing", async () => {
  const response = await handleApp(request(phone, "POST", "https://relay.example.com/apps/relay/api/pebble", { headers: {
    "content-type": "application/json", "X-Index-Delivery": "delivery-1", "X-Pebble-Signature": "sha256=00" },
    body: JSON.stringify({ text: "Buy milk", recordedAt: NOW }) }), env(), null);
  expect(response.status).toBe(404);
  expect(rows("relay_notes")).toEqual([]);
  expect(rows("relay_outbox")).toEqual([]);
});

it("stores a typed note once per phone, with the place its phone sent", async () => {
  const first = await call(phone, "POST", "notes", typed("note-0001", { lat: 43.65, lon: -79.38, accuracy: 8, place: "Home" }));
  expect(first).toEqual({ status: 200, json: { id: expect.any(String), added: true } });
  expect(await call(phone, "POST", "notes", typed("note-0001"))).toEqual({ status: 200, json: { id: first.json.id, added: false } });
  expect((await call(phone, "POST", "notes", typed("note-0002"))).json.added).toBe(true);
  expect(rows("relay_notes").map(row => [row.client_id, row.source, row.lat, row.place, row.place_from])).toEqual([
    ["note-0001", "typed", 43.65, "Home", "phone"], ["note-0002", "typed", null, null, null]]);
});

it("refuses a note from a person, a revoked key or another machine, and a malformed one", async () => {
  for (const who of [matthew, lost, checker, null]) expect((await call(who, "POST", "notes", typed("note-0003"))).status).toBe(403);
  for (const wrong of [typed("short"), typed("note-0004", { lat: 43.6 }), typed("note-0005", { text: "" }), typed("note-0006", { createdAt: NOW / 1000 })]) {
    expect((await call(phone, "POST", "notes", wrong)).status, JSON.stringify(wrong)).toBe(400);
  }
  expect(rows("relay_notes")).toEqual([]);
});

it("stores only the health samples it lacks, and says how many it added", async () => {
  const day = [sample("steps", NOW - 60 * MINUTE, NOW - 30 * MINUTE, 1200), sample("heart_rate", NOW - 10 * MINUTE, NOW - 10 * MINUTE, 72)];
  expect(await call(phone, "POST", "health", { samples: day.slice(0, 1) })).toEqual({ status: 200, json: { received: 1, added: 1 } });
  expect(await call(phone, "POST", "health", { samples: day })).toEqual({ status: 200, json: { received: 2, added: 1 } });
  // The same span from another source, or another phone, is its own sample.
  expect((await call(ipad, "POST", "health", { samples: [{ ...day[0], source: "Apple Health" }] })).json.added).toBe(1);
  expect(rows("relay_health")).toHaveLength(3);
  for (const wrong of [[], [sample("mood", NOW, NOW, 1)], [sample("steps", NOW, NOW - 1, 1)], Array(501).fill(day[0])]) {
    expect((await call(phone, "POST", "health", { samples: wrong })).status).toBe(400);
  }
  expect((await call(lost, "POST", "health", { samples: day })).status).toBe(403);
});

it("stores a batch of every health type the phone sends, each in its own unit", async () => {
  const units = { weight: "kg", resting_heart_rate: "bpm", hrv_sdnn: "ms", hrv_rmssd: "ms", blood_oxygen: "%", blood_pressure_systolic: "mmHg",
    blood_pressure_diastolic: "mmHg", cycle_flow: "flow", mindful: "min", water: "ml" };
  const samples = Object.entries(units).map(([type, unit], index) => sample(type, NOW - index * MINUTE, NOW - index * MINUTE, 2, { unit }));
  expect(await call(phone, "POST", "health", { samples })).toEqual({ status: 200, json: { received: 10, added: 10 } });
  expect(rows("relay_health").map(row => row.type)).toEqual(Object.keys(units));
});

it("stores location points once, and gives no stored ring note a place from them", async () => {
  ringNote("aaaaaaaa-0000-4000-8000-000000000001", NOW - 20 * MINUTE);
  ringNote("aaaaaaaa-0000-4000-8000-000000000002", NOW - 2 * 60 * MINUTE);
  const points = [point(NOW - 23 * MINUTE), point(NOW - 12 * MINUTE, { lat: 43.66, place: undefined })];
  expect(await call(phone, "POST", "locations", { points })).toEqual({ status: 200, json: { received: 2, added: 2 } });
  expect(await call(phone, "POST", "locations", { points })).toEqual({ status: 200, json: { received: 2, added: 0 } });
  expect(rows("relay_notes").map(row => [row.place, row.lat, row.place_from])).toEqual([[null, null, null], [null, null, null]]);
  expect(rows("relay_outbox").map(row => row.kind)).not.toContain("note.updated");
  expect(rows("relay_locations").map(row => row.place)).toEqual(["Queen St W", null]);
  expect((await call(phone, "POST", "locations", { points: [point(NOW, { lat: 91 })] })).status).toBe(400);
  expect((await call(matthew, "POST", "locations", { points })).status).toBe(403);
});

it("reads the timeline newest first, a page at a time, for the site page, and refuses a device key", async () => {
  ringNote("aaaaaaaa-0000-4000-8000-000000000001", NOW - 3 * MINUTE);
  await call(phone, "POST", "notes", typed("note-0001", { createdAt: NOW - 2 * MINUTE, lat: 43.65, lon: -79.38 }));
  await call(phone, "POST", "notes", typed("note-0002", { createdAt: NOW - MINUTE }));
  const all = await call(matthew, "GET", "timeline");
  expect(all.status).toBe(200);
  expect(all.json.notes.map(note => [note.source, note.device, note.audio, note.place])).toEqual([
    ["typed", "Android phone", false, null],
    ["typed", "Android phone", false, { lat: 43.65, lon: -79.38, accuracy: null, name: null, from: "phone" }],
    ["ring", "iPad", true, null]]);
  expect(all.json.next).toBeNull();
  const first = await call(matthew, "GET", "timeline", { limit: 2 });
  expect([first.json.notes.length, first.json.next, first.json.nextId]).toEqual([2, NOW - 2 * MINUTE, first.json.notes[1].id]);
  const rest = await call(matthew, "GET", "timeline", { limit: 2, before: first.json.next, beforeId: first.json.nextId });
  expect(rest.json.notes.map(note => note.id)).toEqual([RING]);
  expect((await call(matthew, "GET", "timeline", { limit: 101 })).status).toBe(400);
  for (const [who, status] of [[phone, 403], [laptop, 403], [lost, 403], [null, 401]] as const) {
    expect((await call(who, "GET", "timeline")).status).toBe(status);
  }
});

it("pages past two notes that share a time, one at a time, missing neither", async () => {
  ringNote("aaaaaaaa-0000-4000-8000-000000000001", NOW - MINUTE);
  ringNote("aaaaaaaa-0000-4000-8000-000000000002", NOW - MINUTE);
  const seen: unknown[] = [];
  let page = await call(matthew, "GET", "timeline", { limit: 1 });
  while (true) {
    seen.push(...page.json.notes.map(note => note.id));
    if (page.json.next === null) break;
    page = await call(matthew, "GET", "timeline", { limit: 1, before: page.json.next, beforeId: page.json.nextId });
  }
  expect(seen).toEqual(["aaaaaaaa-0000-4000-8000-000000000002", "aaaaaaaa-0000-4000-8000-000000000001"]);
});

it("sums a day for the site page: notes, the larger phone's steps and sleep, heart rate, workouts and places", async () => {
  const start = Date.UTC(2026, 10, 5) + 5 * 60 * MINUTE;
  await call(phone, "POST", "health", { samples: [
    sample("steps", start + 60 * MINUTE, start + 90 * MINUTE, 3000), sample("steps", start + 120 * MINUTE, start + 150 * MINUTE, 5214),
    sample("heart_rate", start + 60 * MINUTE, start + 60 * MINUTE, 61), sample("heart_rate", start + 70 * MINUTE, start + 70 * MINUTE, 90),
    sample("sleep", start - 7 * 60 * MINUTE, start + 30 * MINUTE, 450), sample("workout", start + 3 * 60 * MINUTE, start + 3 * 60 * MINUTE + 45 * MINUTE, 45)] });
  await call(ipad, "POST", "health", { samples: [sample("steps", start + 60 * MINUTE, start + 90 * MINUTE, 4000)] });
  await call(phone, "POST", "locations", { points: [point(start + 60 * MINUTE), point(start + 90 * MINUTE),
    point(start + 3 * 60 * MINUTE, { lat: 43.6629, lon: -79.3957, place: undefined })] });
  await call(phone, "POST", "notes", typed("note-0001", { createdAt: start + 61 * MINUTE }));
  await call(phone, "POST", "notes", typed("note-0002", { createdAt: start - 6 * 60 * MINUTE }));
  const { status, json } = await call(matthew, "GET", "summary", { day: "2026-11-05", offset: -300 });
  expect(status).toBe(200);
  expect(json).toEqual({ day: "2026-11-05", notes: 1, steps: 8214, sleepMinutes: 450, heartRate: { min: 61, max: 90, average: 76 },
    workouts: { count: 1, minutes: 45 }, places: [
      { name: "Queen St W", lat: 43.6487, lon: -79.3962, from: start + 60 * MINUTE, to: start + 90 * MINUTE },
      { name: "43.663, -79.396", lat: 43.6629, lon: -79.3957, from: start + 3 * 60 * MINUTE, to: start + 3 * 60 * MINUTE }], events: [] });
  expect((await call(matthew, "GET", "summary", { day: "2026-11-04" })).json).toEqual({ day: "2026-11-04", notes: 1, steps: 0, sleepMinutes: 0,
    heartRate: null, workouts: { count: 0, minutes: 0 }, places: [], events: [] });
  for (const day of ["yesterday", "2026-13-45"]) expect((await call(matthew, "GET", "summary", { day })).status).toBe(400);
  for (const [who, status] of [[phone, 403], [null, 401]] as const) expect((await call(who, "GET", "summary", { day: "2026-11-05" })).status).toBe(status);
});

it("takes the larger source's steps and sleep when a phone and its watch both count them", async () => {
  const start = Date.UTC(2026, 10, 5, 12);
  const watch = { source: "com.apple.health.watch" };
  await call(phone, "POST", "health", { samples: [
    sample("steps", start, start + 30 * MINUTE, 3000), sample("steps", start, start + 30 * MINUTE, 3200, watch),
    sample("steps", start + 60 * MINUTE, start + 90 * MINUTE, 1000, watch),
    sample("sleep", start - 8 * 60 * MINUTE, start - MINUTE, 479), sample("sleep", start - 8 * 60 * MINUTE, start - 60 * MINUTE, 420, watch)] });
  const { json } = await call(matthew, "GET", "summary", { day: "2026-11-05" });
  expect([json.steps, json.sleepMinutes]).toEqual([4200, 479]);
});

it("streams a ring note's recording, and answers not found for a note without one", async () => {
  ringNote(RING, NOW);
  await seal(RING, [1, 2, 3]);
  const played = await play(matthew, RING);
  expect([played.status, played.headers.get("content-type"), played.headers.get("content-length")]).toEqual([200, "audio/mp4", "3"]);
  expect(new Uint8Array(await played.arrayBuffer())).toEqual(new Uint8Array([1, 2, 3]));
  await call(phone, "POST", "notes", typed("note-0001"));
  const typedId = rows("relay_notes")[1].id as string;
  ringNote("aaaaaaaa-0000-4000-8000-000000000002", NOW);
  for (const [id, status] of [[typedId, 404], ["aaaaaaaa-0000-4000-8000-000000000002", 404], ["bbbbbbbb-0000-4000-8000-000000000003", 404], ["../x", 400]]) {
    expect((await call(matthew, "GET", "audio", { id })).status, String(id)).toBe(status);
  }
  expect((await call(matthew, "GET", "audio")).status).toBe(400);
  // A device key only sends: it plays no recording.
  for (const [who, status] of [[phone, 403], [ipad, 403], [null, 401]] as const) expect((await play(who, RING)).status).toBe(status);
});

it("answers one byte range of a recording, as Safari asks before it plays", async () => {
  ringNote(RING, NOW);
  await seal(RING, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  const part = async (range: string) => {
    const response = await play(matthew, RING, range);
    return [response.status, response.headers.get("content-range"), response.headers.get("content-length"), [...new Uint8Array(await response.arrayBuffer())]];
  };
  expect(await part("bytes=0-1")).toEqual([206, "bytes 0-1/10", "2", [0, 1]]);
  expect(await part("bytes=7-")).toEqual([206, "bytes 7-9/10", "3", [7, 8, 9]]);
  expect(await part("bytes=-2")).toEqual([206, "bytes 8-9/10", "2", [8, 9]]);
  expect(await part("bytes=8-50")).toEqual([206, "bytes 8-9/10", "2", [8, 9]]);
  expect((await part("bytes=10-")).slice(0, 2)).toEqual([416, "bytes */10"]);
  // Several ranges, or a range it can't read, get the whole file.
  for (const range of ["bytes=0-1,4-5", "bytes=5-2", "items=0-1"]) expect((await part(range))[0], range).toBe(200);
  expect((await part("bytes=-0")).slice(0, 2)).toEqual([416, "bytes */10"]);
  ringNote("aaaaaaaa-0000-4000-8000-000000000002", NOW);
  expect((await play(matthew, "aaaaaaaa-0000-4000-8000-000000000002", "bytes=0-1")).status).toBe(404);
});

it("wakes the webhooks that take what was stored, and none for a repeat", async () => {
  const webhook = db.sql.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at)
    VALUES (?, 'Example database', 'https://db.example.com/relay', 'whsec_AAAA', ?, 0, ?)`);
  webhook.run("notes", '["notes"]', NOW);
  webhook.run("health", '["notes","health"]', NOW);
  await call(phone, "POST", "notes", typed("note-0001"));
  await call(phone, "POST", "notes", typed("note-0001"));
  expect(queue.sent).toEqual([{ webhook: "notes", person: ANA }, { webhook: "health", person: ANA }]);
  queue.sent = [];
  const day = [sample("steps", NOW - 60 * MINUTE, NOW - 30 * MINUTE, 1200)];
  await call(phone, "POST", "health", { samples: day });
  await call(phone, "POST", "health", { samples: day });
  await call(phone, "POST", "locations", { points: [point(NOW - 23 * MINUTE)] });
  expect(queue.sent).toEqual([{ webhook: "health", person: ANA }]);
});

it("tells a device key its own name, and nothing else, and refuses everyone else", async () => {
  expect(await call(phone, "GET", "key")).toEqual({ status: 200, json: { device: "Android phone" } });
  expect(await call(laptop, "GET", "key")).toEqual({ status: 200, json: { device: "Laptop" } });
  for (const who of [matthew, lost, checker, null]) expect((await call(who, "GET", "key")).status).toBe(403);
});

it("answers an empty name for a key whose device is no longer in the space", async () => {
  const gone = makeKey("gone");
  directoryDb.sql.prepare("INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at) VALUES (?, ?, 'd-gone', 'phone', ?)")
    .run(await hashToken(gone), ANA, NOW);
  expect(await call({ bearer: gone }, "GET", "key")).toEqual({ status: 200, json: { device: "" } });
});

it("answers 503 on a server with no spaces, as a preview has none", async () => {
  expect((await call(phone, "POST", "notes", typed("note-0099"), { SPACES: undefined })).status).toBe(503);
  expect((await call(matthew, "GET", "timeline", {}, { SPACES: undefined })).status).toBe(503);
});
