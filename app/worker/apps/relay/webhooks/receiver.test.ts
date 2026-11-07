import { spawn, type ChildProcess } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { afterAll, beforeAll, expect, it } from "vitest";
import { healthSamples, locationPoints, noteCreated, noteUpdated, webhookTest, type NoteRow } from "./format.ts";
import { base64, newSecret } from "./sign.ts";
import { post } from "./send.ts";

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

const device = { device_id: "d0000000-0000-4000-8000-000000000002", device_name: "Pebble app" };
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
  expect((await send(messages[0], newSecret())).status).toBe(401);
  expect((await fetch(address)).status).toBe(401);
  const saved = new DatabaseSync(database, { readOnly: true });
  expect(saved.prepare("SELECT id, place, lat, hex(audio) AS audio FROM notes").all().map(row => ({ ...row }))).toEqual([
    { id: ring.id, place: "Harbord St", lat: 43.6629, audio: "00000018" }]);
  expect(saved.prepare("SELECT id, type, value FROM health_samples").all().map(row => ({ ...row }))).toEqual([{ id: 2, type: "steps", value: 5210 }]);
  expect(saved.prepare("SELECT id, place FROM location_points").all().map(row => ({ ...row }))).toEqual([{ id: 1, place: null }]);
  saved.close();
});

// The phone's own messages, as mobile/test/webhook_test.dart writes them, signed again with this receiver's secret.
const phone = (type: string) =>
  (JSON.parse(readFileSync(new URL(`../../../../../mobile/test/fixtures/webhook/${type}.json`, import.meta.url), "utf8")) as { body: string }).body;

it("saves what the phone sends to its own webhook, with each file's bytes beside its note", async () => {
  const types = ["note.created", "note.file", "health.samples", "location.points", "webhook.test"];
  for (const type of types) expect((await post(`${address}/`, secret, `phone_${type}`, phone(type))).status, type).toBe(204);
  const note = JSON.parse(phone("note.created")).data.note;
  const saved = new DatabaseSync(database, { readOnly: true });
  expect(saved.prepare("SELECT f.name, hex(f.bytes) AS bytes FROM files f JOIN notes n ON n.id = f.note_id WHERE n.id = ?").all(note.id)
    .map(row => ({ ...row }))).toEqual([{ name: "receipt.jpg", bytes: "01020304" }]);
  // The phone numbers its samples from 1 too: its own device id keeps them apart from the server's.
  expect(saved.prepare("SELECT count(*) AS n FROM health_samples WHERE device_id = ?").get(note.device.id)).toEqual({ n: 1 });
  saved.close();
});
