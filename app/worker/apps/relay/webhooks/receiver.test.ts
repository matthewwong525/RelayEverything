import { spawn, type ChildProcess } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { afterAll, beforeAll, expect, it } from "vitest";
import { healthNights, healthSamples, locationPoints, locationStays, noteCreated, noteDeleted, noteFile, noteUpdated, photoCreated, webhookTest, type NoteRow } from "./format.ts";
import { base64, newSecret } from "./sign.ts";
import { bodyWithFile, post } from "./send.ts";

// The example receiver the website offers, run as a person runs it, and fed by the real sender.
const receiver = new URL("../../../../../site/public/webhooks/receiver.mjs", import.meta.url);
const secret = newSecret();
const folder = mkdtempSync(join(tmpdir(), "relay-receiver-"));
const database = join(folder, "relay.sqlite");
const children: ChildProcess[] = [];
let address = "";

/** Starts the receiver on [file] and gives its address. */
async function start(file: string): Promise<string> {
  const child = spawn(process.execPath, [receiver.pathname], { env: { ...process.env, RELAY_WEBHOOK_SECRET: secret, PORT: "0", DATABASE: file } });
  children.push(child);
  return new Promise(resolve => child.stdout!.on("data", (chunk: Buffer) => resolve(/http:\S+/.exec(String(chunk))![0])));
}

beforeAll(async () => {
  address = await start(database);
});
afterAll(() => {
  children.forEach(child => child.kill());
  rmSync(folder, { recursive: true, force: true });
});

const device = { device_id: "d0000000-0000-4000-8000-000000000002", device_name: "iPad" };
const ring: NoteRow = { id: "a0000000-0000-4000-8000-000000000001", source: "ring", text: "Call the PCB fab about the second batch.",
  recorded_at: Date.UTC(2026, 10, 4, 14, 1), created_at: Date.UTC(2026, 10, 4, 14, 1, 2), ...device,
  audio_key: "notes/a0000000-0000-4000-8000-000000000001.m4a" };
const send = (body: object, key = secret) => post(`${address}/`, key, `msg_${Math.random()}`, JSON.stringify(body));

it("saves what Relay sends, once each, and refuses a message signed with another secret", async () => {
  const changed = { ...ring, text: "Call the PCB fab about the third batch." };
  const at = Date.now();
  const messages = [noteCreated(ring, base64(new Uint8Array([0, 0, 0, 24])), at), noteCreated(ring, base64(new Uint8Array([0, 0, 0, 24])), at),
    noteUpdated(changed, at), webhookTest({ id: "hook", name: "Mine" }, at),
    healthSamples([{ id: 2, ...device, type: "steps", start_at: at, end_at: at + 1000, value: 5210, unit: "count", source: "fitness" },
      { id: 4, ...device, type: "workout", start_at: at, end_at: at + 1_920_000, value: 32, unit: "min", source: "watch", kind: "running",
        distance: 5100, calories: 410 }], at),
    healthNights([{ id: 5, ...device, source: "watch", start_at: at - 28_800_000, end_at: at, asleep_at: at - 27_900_000, woke_at: at,
      asleep: 430, core: 245, deep: 75, rem: 110, awake: 25, stages: JSON.stringify([{ stage: "deep", start: at - 27_900_000, end: at - 24_600_000 }]) }], at),
    locationPoints([{ id: 1, ...device, at, lat: 43.6629, lon: -79.3957, accuracy: 15, place: null }], at),
    locationStays([{ id: 3, ...device, kind: "stay", start_at: at, end_at: at + 600_000, ongoing: 1, lat: 43.6629, lon: -79.3957,
      name: "Corner Café", address: "Harbord St", event: null, source: "map", mode: null, km: null }], at),
    locationStays([{ id: 3, ...device, kind: "stay", start_at: at, end_at: at + 3_600_000, ongoing: 0, lat: 43.6629, lon: -79.3957,
      name: "Corner Café", address: "Harbord St", event: null, source: "map", mode: null, km: null }], at)];
  for (const message of messages) expect((await send(message)).status, message.type).toBe(204);
  const photo = photoCreated({ id: "p0000000-0000-4000-8000-000000000001", ...device, taken_at: at, lat: 38.7139, lon: -9.1394, width: 1600,
    height: 1200, bytes: 4 }, at);
  expect((await post(`${address}/`, secret, "msg_photo", bodyWithFile({ message: photo, bytes: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]) }))).status)
    .toBe(204);
  expect((await send(messages[0], newSecret())).status).toBe(401);
  expect((await fetch(address)).status).toBe(401);
  const saved = new DatabaseSync(database, { readOnly: true });
  // A note has no place: the receiver keeps its place columns, written null, so a database made before still opens.
  expect(saved.prepare("SELECT id, text, place, lat, hex(audio) AS audio FROM notes").all().map(row => ({ ...row }))).toEqual([
    { id: ring.id, text: changed.text, place: null, lat: null, audio: "00000018" }]);
  expect(saved.prepare("SELECT id, type, value FROM health_samples").all().map(row => ({ ...row }))).toEqual([{ id: 2, type: "steps", value: 5210 },
    { id: 4, type: "workout", value: 32 }]);
  expect(saved.prepare("SELECT id, kind, distance, calories FROM workouts").all().map(row => ({ ...row }))).toEqual([
    { id: 4, kind: "running", distance: 5100, calories: 410 }]);
  expect(saved.prepare("SELECT id, deep, json_extract(stages, '$[0].stage') AS first FROM health_nights").all().map(row => ({ ...row })))
    .toEqual([{ id: 5, deep: 75, first: "deep" }]);
  expect(saved.prepare("SELECT id, place FROM location_points").all().map(row => ({ ...row }))).toEqual([{ id: 1, place: null }]);
  // The stay's second message, with its end, updates the first's row.
  expect(saved.prepare("SELECT id, name, ongoing FROM location_stays").all().map(row => ({ ...row }))).toEqual([
    { id: 3, name: "Corner Café", ongoing: 0 }]);
  expect(saved.prepare("SELECT id, lat, width, hex(bytes) AS bytes FROM photos").all().map(row => ({ ...row }))).toEqual([
    { id: "p0000000-0000-4000-8000-000000000001", lat: 38.7139, width: 1600, bytes: "FFD8FFD9" }]);
  saved.close();
});

it("keeps each file a note lists, then its bytes beside the note when they come", async () => {
  const at = Date.now();
  const listed = { id: "file-list-0001", name: "warranty.pdf", content_type: "application/pdf", size: 3 };
  const typed = { ...ring, id: "a0000000-0000-4000-8000-000000000009", source: "typed" as const, audio_key: null };
  const files = [listed, { ...listed, id: "file-list-0002", name: "never.pdf" }];
  for (let tries = 0; tries < 2; tries++) expect((await send(noteCreated(typed, null, at, files))).status).toBe(204);
  const bytes = new Uint8Array([1, 2, 3]);
  expect((await post(`${address}/`, secret, "msg_file", bodyWithFile({ message: noteFile(listed, typed.id, at), bytes }))).status).toBe(204);
  // A resent note.created keeps the bytes that came.
  expect((await send(noteCreated(typed, null, at, files))).status).toBe(204);
  const saved = new DatabaseSync(database, { readOnly: true });
  expect(saved.prepare("SELECT id, note_id, name, iif(bytes IS NULL, NULL, hex(bytes)) AS bytes FROM files WHERE note_id = ? ORDER BY id").all(typed.id)
    .map(row => ({ ...row }))).toEqual([{ id: "file-list-0001", note_id: typed.id, name: "warranty.pdf", bytes: "010203" },
    { id: "file-list-0002", note_id: typed.id, name: "never.pdf", bytes: null }]);
  saved.close();
});

it("keeps a changed note's latest words and its recording, and lists a file added with the change", async () => {
  const at = Date.now();
  const note = { ...ring, id: "a0000000-0000-4000-8000-000000000010" };
  const added = { id: "file-edit-0001", name: "list.pdf", content_type: "application/pdf", size: 3 };
  expect((await send(noteCreated(note, base64(new Uint8Array([0, 0, 0, 24])), at))).status).toBe(204);
  expect((await send(noteUpdated({ ...note, text: "# Fab\n- [ ] Call about the second batch", edited_at: at }, at, [added]))).status).toBe(204);
  const saved = new DatabaseSync(database, { readOnly: true });
  expect({ ...saved.prepare("SELECT text, hex(audio) AS audio FROM notes WHERE id = ?").get(note.id) })
    .toEqual({ text: "# Fab\n- [ ] Call about the second batch", audio: "00000018" });
  expect(saved.prepare("SELECT id FROM files WHERE note_id = ?").all(note.id).map(row => row.id)).toEqual([added.id]);
  saved.close();
});

it("deletes a deleted note and its files, and another note stays", async () => {
  const at = Date.now();
  const note = { ...ring, id: "a0000000-0000-4000-8000-000000000011", audio_key: null };
  const listed = { id: "file-gone-0001", name: "ticket.pdf", content_type: "application/pdf", size: 3 };
  expect((await send(noteCreated(note, null, at, [listed]))).status).toBe(204);
  for (let tries = 0; tries < 2; tries++) expect((await send(noteDeleted(note.id, at))).status).toBe(204);
  const saved = new DatabaseSync(database, { readOnly: true });
  expect(saved.prepare("SELECT count(*) AS n FROM notes WHERE id = ?").get(note.id)).toEqual({ n: 0 });
  expect(saved.prepare("SELECT count(*) AS n FROM files WHERE note_id = ?").get(note.id)).toEqual({ n: 0 });
  expect(saved.prepare("SELECT count(*) AS n FROM notes WHERE id = ?").get(ring.id)).toEqual({ n: 1 });
  saved.close();
});

// The phone's own messages, as mobile/test/webhook_test.dart writes them, signed again with this receiver's secret.
const phone = (type: string) =>
  (JSON.parse(readFileSync(new URL(`../../../../../mobile/test/fixtures/webhook/${type}.json`, import.meta.url), "utf8")) as { body: string }).body;

it("saves what the phone sends to its own webhook, with each file's bytes beside its note", async () => {
  const types = ["note.created", "note.file", "note.updated", "health.samples", "location.points", "calendar.events", "photo.created", "webhook.test"];
  for (const type of types) expect((await post(`${address}/`, secret, `phone_${type}`, phone(type))).status, type).toBe(204);
  const note = JSON.parse(phone("note.created")).data.note;
  const saved = new DatabaseSync(database, { readOnly: true });
  expect(saved.prepare("SELECT f.name, hex(f.bytes) AS bytes FROM files f JOIN notes n ON n.id = f.note_id WHERE n.id = ?").all(note.id)
    .map(row => ({ ...row }))).toEqual([{ name: "receipt.jpg", bytes: "01020304" }]);
  // The phone's own device id keeps its samples apart from the server's.
  expect(saved.prepare("SELECT count(*) AS n FROM health_samples WHERE device_id = ?").get(note.device.id)).toEqual({ n: 2 });
  expect(saved.prepare("SELECT kind FROM workouts WHERE device_id = ?").get(note.device.id)).toEqual({ kind: "running" });
  expect(saved.prepare("SELECT status, title, all_day FROM calendar_events WHERE device_id = ? ORDER BY status").all(note.device.id)
    .map(row => ({ ...row }))).toEqual([{ status: "changed", title: "Board meeting", all_day: 0 }, { status: "removed", title: null, all_day: 0 }]);
  const photo = JSON.parse(phone("photo.created")).data.photo;
  expect(saved.prepare("SELECT device_id, taken_at, size FROM photos WHERE id = ?").get(photo.id))
    .toEqual({ device_id: note.device.id, taken_at: photo.taken_at, size: photo.size });
  expect(saved.prepare("SELECT count(*) AS n FROM other_messages").get()).toEqual({ n: 0 });
  saved.close();
  // The phone's note.deleted names the note as its note.created did: the note and its file go.
  expect((await post(`${address}/`, secret, "phone_note.deleted", phone("note.deleted"))).status).toBe(204);
  const after = new DatabaseSync(database, { readOnly: true });
  expect(after.prepare("SELECT (SELECT count(*) FROM notes WHERE id = ?) + (SELECT count(*) FROM files WHERE note_id = ?) AS n")
    .get(note.id, note.id)).toEqual({ n: 0 });
  after.close();
});

const run = { ...device, device_id: "d0000000-0000-4000-8000-000000000003", type: "workout" as const, start_at: Date.UTC(2026, 10, 4, 11, 10),
  end_at: Date.UTC(2026, 10, 4, 11, 42), value: 32, unit: "min", source: "watch", kind: "running", distance: 5100, calories: 410 };

it("keeps a sample once by device, type, start, end and source, when it comes again with a new id", async () => {
  for (const id of [1, 281_474_976_710_655]) expect((await send(healthSamples([{ ...run, id }], Date.now()))).status).toBe(204);
  const saved = new DatabaseSync(database, { readOnly: true });
  expect(saved.prepare("SELECT id FROM health_samples WHERE device_id = ?").all(run.device_id).map(row => row.id)).toEqual([281_474_976_710_655]);
  expect(saved.prepare("SELECT id FROM workouts WHERE device_id = ?").all(run.device_id).map(row => row.id)).toEqual([281_474_976_710_655]);
  saved.close();
});

it("opens a database from before, and a sample saved there under an old id is kept once", async () => {
  const old = join(folder, "old.sqlite");
  const made = new DatabaseSync(old);
  made.exec(`CREATE TABLE health_samples (id INTEGER, device_id TEXT, type TEXT, start TEXT, "end" TEXT, value REAL, unit TEXT, source TEXT,
      PRIMARY KEY (device_id, id));
    CREATE TABLE workouts (id INTEGER, device_id TEXT, kind TEXT, distance REAL, calories REAL, PRIMARY KEY (device_id, id));`);
  const [startIso, endIso] = [new Date(run.start_at).toISOString(), new Date(run.end_at).toISOString()];
  for (const id of [7, 8]) made.prepare("INSERT INTO health_samples VALUES (?, ?, 'workout', ?, ?, 32, 'min', 'watch')").run(id, run.device_id, startIso, endIso);
  made.prepare("INSERT INTO workouts VALUES (7, ?, NULL, NULL, NULL)").run(run.device_id);
  made.close();
  expect((await post(`${await start(old)}/`, secret, "msg_old", JSON.stringify(healthSamples([{ ...run, id: 99 }], Date.now())))).status).toBe(204);
  const saved = new DatabaseSync(old, { readOnly: true });
  expect(saved.prepare("SELECT id FROM health_samples").all().map(row => row.id)).toEqual([99]);
  expect(saved.prepare("SELECT id, kind FROM workouts").all().map(row => ({ ...row }))).toEqual([{ id: 99, kind: "running" }]);
  saved.close();
});

it("answers 2xx to a type it does not know yet and keeps it as one raw row, once, however often it comes", async () => {
  const body = JSON.stringify({ version: 1, type: "photo.added", timestamp: new Date().toISOString(), data: { photo: { id: "p-1" } } });
  for (let tries = 0; tries < 2; tries++) expect((await post(`${address}/`, secret, "msg_new_type", body)).status).toBe(204);
  const saved = new DatabaseSync(database, { readOnly: true });
  expect(saved.prepare("SELECT webhook_id, type, body FROM other_messages").all().map(row => ({ ...row }))).toEqual([
    { webhook_id: "msg_new_type", type: "photo.added", body }]);
  saved.close();
});
