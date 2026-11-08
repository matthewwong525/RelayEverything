import { spawn, type ChildProcess } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { afterAll, beforeAll, expect, it } from "vitest";
import { healthSamples, locationPoints, noteCreated, noteFile, noteUpdated, photoCreated, webhookTest, type NoteRow } from "./format.ts";
import { base64, newSecret } from "./sign.ts";
import { bodyWithFile, post } from "./send.ts";

// The example receiver the website offers, run as a person runs it, and fed by the real sender.
const receiver = new URL("../../../../../site/public/webhooks/receiver.mjs", import.meta.url);
const secret = newSecret();
const folder = mkdtempSync(join(tmpdir(), "relay-receiver-"));
const database = join(folder, "relay.sqlite");
let child: ChildProcess;
let address = "";

beforeAll(async () => {
  child = spawn(process.execPath, [receiver.pathname], { env: { ...process.env, RELAY_WEBHOOK_SECRET: secret, PORT: "0", DATABASE: database } });
  address = await new Promise(resolve => child.stdout!.on("data", (chunk: Buffer) => resolve(/http:\S+/.exec(String(chunk))![0])));
});
afterAll(() => {
  child.kill();
  rmSync(folder, { recursive: true, force: true });
});

const device = { device_id: "d0000000-0000-4000-8000-000000000002", device_name: "iPad" };
const ring: NoteRow = { id: "a0000000-0000-4000-8000-000000000001", source: "ring", text: "Call the PCB fab about the second batch.",
  recorded_at: Date.UTC(2026, 10, 4, 14, 1), created_at: Date.UTC(2026, 10, 4, 14, 1, 2), ...device, lat: null, lon: null, accuracy: null,
  place: null, place_from: null, audio_key: "notes/a0000000-0000-4000-8000-000000000001.m4a" };
const send = (body: object, key = secret) => post(`${address}/`, key, `msg_${Math.random()}`, JSON.stringify(body));

it("saves what Relay sends, once each, and refuses a message signed with another secret", async () => {
  const placed = { ...ring, lat: 43.6629, lon: -79.3957, accuracy: 15, place: "Harbord St", place_from: "history" as const };
  const at = Date.now();
  const messages = [noteCreated(ring, base64(new Uint8Array([0, 0, 0, 24])), at), noteCreated(ring, base64(new Uint8Array([0, 0, 0, 24])), at),
    noteUpdated(placed, at), webhookTest({ id: "hook", name: "Mine" }, at),
    healthSamples([{ id: 2, ...device, type: "steps", start_at: at, end_at: at + 1000, value: 5210, unit: "count", source: "fitness" }], at),
    locationPoints([{ id: 1, ...device, at, lat: 43.6629, lon: -79.3957, accuracy: 15, place: null }], at)];
  for (const message of messages) expect((await send(message)).status, message.type).toBe(204);
  const photo = photoCreated({ id: "p0000000-0000-4000-8000-000000000001", ...device, taken_at: at, lat: 38.7139, lon: -9.1394, width: 1600,
    height: 1200, bytes: 4 }, at);
  expect((await post(`${address}/`, secret, "msg_photo", bodyWithFile({ message: photo, bytes: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]) }))).status)
    .toBe(204);
  expect((await send(messages[0], newSecret())).status).toBe(401);
  expect((await fetch(address)).status).toBe(401);
  const saved = new DatabaseSync(database, { readOnly: true });
  expect(saved.prepare("SELECT id, place, lat, hex(audio) AS audio FROM notes").all().map(row => ({ ...row }))).toEqual([
    { id: ring.id, place: "Harbord St", lat: 43.6629, audio: "00000018" }]);
  expect(saved.prepare("SELECT id, type, value FROM health_samples").all().map(row => ({ ...row }))).toEqual([{ id: 2, type: "steps", value: 5210 }]);
  expect(saved.prepare("SELECT id, place FROM location_points").all().map(row => ({ ...row }))).toEqual([{ id: 1, place: null }]);
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

// The phone's own messages, as mobile/test/webhook_test.dart writes them, signed again with this receiver's secret.
const phone = (type: string) =>
  (JSON.parse(readFileSync(new URL(`../../../../../mobile/test/fixtures/webhook/${type}.json`, import.meta.url), "utf8")) as { body: string }).body;

it("saves what the phone sends to its own webhook, with each file's bytes beside its note", async () => {
  const types = ["note.created", "note.file", "health.samples", "location.points", "calendar.events", "photo.created", "webhook.test"];
  for (const type of types) expect((await post(`${address}/`, secret, `phone_${type}`, phone(type))).status, type).toBe(204);
  const note = JSON.parse(phone("note.created")).data.note;
  const saved = new DatabaseSync(database, { readOnly: true });
  expect(saved.prepare("SELECT f.name, hex(f.bytes) AS bytes FROM files f JOIN notes n ON n.id = f.note_id WHERE n.id = ?").all(note.id)
    .map(row => ({ ...row }))).toEqual([{ name: "receipt.jpg", bytes: "01020304" }]);
  // The phone numbers its samples from 1 too: its own device id keeps them apart from the server's.
  expect(saved.prepare("SELECT count(*) AS n FROM health_samples WHERE device_id = ?").get(note.device.id)).toEqual({ n: 1 });
  expect(saved.prepare("SELECT status, title, all_day FROM calendar_events WHERE device_id = ? ORDER BY status").all(note.device.id)
    .map(row => ({ ...row }))).toEqual([{ status: "changed", title: "Board meeting", all_day: 0 }, { status: "removed", title: null, all_day: 0 }]);
  const photo = JSON.parse(phone("photo.created")).data.photo;
  expect(saved.prepare("SELECT device_id, taken_at, size FROM photos WHERE id = ?").get(photo.id))
    .toEqual({ device_id: note.device.id, taken_at: photo.taken_at, size: photo.size });
  expect(saved.prepare("SELECT count(*) AS n FROM other_messages").get()).toEqual({ n: 0 });
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
