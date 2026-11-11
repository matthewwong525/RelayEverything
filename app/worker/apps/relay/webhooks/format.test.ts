import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { Webhook } from "standardwebhooks";
import { afterEach, expect, it, vi } from "vitest";
import { z } from "zod";
import * as format from "./format.ts";
import { calendarEvents, healthNights, healthSamples, jsonSchema, locationPoints, locationStays, message, noteCreated, noteDeleted, noteFile, noteUpdated, photoCreated,
  webhookTest, type NoteRow } from "./format.ts";
import { base64, newSecret, signedHeaders } from "./sign.ts";

const schemaFile = new URL("../../../../../site/public/webhooks/v1.schema.json", import.meta.url);
const AT = Date.UTC(2026, 10, 4, 14, 1, 2);
const device = { device_id: "d0000000-0000-4000-8000-000000000002", device_name: "iPad" };
const ring: NoteRow = { id: "a0000000-0000-4000-8000-000000000001", source: "ring", text: "Call the PCB fab about the second batch.",
  recorded_at: Date.UTC(2026, 10, 4, 14, 1), created_at: AT, ...device, audio_key: "notes/a0000000-0000-4000-8000-000000000001.m4a" };
const typed: NoteRow = { ...ring, id: "a0000000-0000-4000-8000-000000000002", source: "typed", audio_key: null };

it("builds each type in the published format, with times in ISO 8601 and a recording in base64", () => {
  const built = [
    noteCreated(ring, base64(new Uint8Array([0, 0, 0, 24])), AT), noteCreated(typed, null, AT), noteUpdated(ring, AT),
    healthSamples([{ id: 2, ...device, type: "steps", start_at: AT, end_at: AT + 1000, value: 5210, unit: "count", source: "fitness" }], AT),
    locationPoints([{ id: 1, ...device, at: AT, lat: 43.6629, lon: -79.3957, accuracy: 15, place: null }], AT),
    webhookTest({ id: "e0000000-0000-4000-8000-000000000001", name: "Example database" }, AT),
    noteFile({ id: "file-pdf-0001", name: "warranty.pdf", content_type: "application/pdf", size: 245_760 }, typed.id, AT),
    noteDeleted(typed.id, AT),
    locationStays([{ id: 3, ...device, kind: "stay", start_at: AT, end_at: AT + 600_000, ongoing: 1, lat: 43.6629, lon: -79.3957,
      name: "Corner Café", address: "Harbord St", event: null, source: "map", mode: null, km: null },
    { id: 4, ...device, kind: "trip", start_at: AT - 900_000, end_at: AT, ongoing: 0, lat: null, lon: null, name: null, address: null,
      event: null, source: null, mode: "driving", km: 6.2 }], AT),
  ];
  for (const item of built) expect(message.parse(item), item.type).toEqual(item);
  expect(built[0]).toEqual({ version: 1, type: "note.created", timestamp: "2026-11-04T14:01:02.000Z", data: { note: {
    id: ring.id, source: "ring", text: ring.text, recorded_at: "2026-11-04T14:01:00.000Z", created_at: "2026-11-04T14:01:02.000Z",
    device: { id: device.device_id, name: "iPad" },
    audio: { content_type: "audio/mp4", base64: "AAAAGA==" } } } });
  expect(built[1].data).toMatchObject({ note: { audio: null } });
  expect(built[1].data).not.toHaveProperty("note.place");
  expect(built[2].data).not.toHaveProperty("note.audio");
  expect(built[3].data).toEqual({ samples: [{ id: 2, device: { id: device.device_id, name: "iPad" }, type: "steps",
    start: "2026-11-04T14:01:02.000Z", end: "2026-11-04T14:01:03.000Z", value: 5210, unit: "count", source: "fitness" }] });
  expect(() => message.parse({ ...built[5], version: 2 })).toThrow();
  // The sender writes the bytes into the empty base64.
  expect(built[6].data).toEqual({ note_id: typed.id, file: { id: "file-pdf-0001", name: "warranty.pdf", content_type: "application/pdf",
    size: 245_760, base64: "" } });
  // A deleted note's row is gone: the message names it by its id alone.
  expect(built[7].data).toEqual({ note: { id: typed.id, deleted_at: "2026-11-04T14:01:02.000Z" } });
  expect(built[8].data).toMatchObject({ stays: [
    { kind: "stay", ongoing: true, start: "2026-11-04T14:01:02.000Z", name: "Corner Café", mode: null, km: null },
    { kind: "trip", ongoing: false, start: "2026-11-04T13:46:02.000Z", name: null, mode: "driving", km: 6.2 }] });
});

afterEach(() => vi.useRealTimers());

it("signs so a Standard Webhooks library takes the body, and refuses a changed body or another secret", async () => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(AT);
  const secret = newSecret();
  expect(secret).toMatch(/^whsec_[A-Za-z0-9+/]{43}=$/);
  const body = JSON.stringify(webhookTest({ id: "hook", name: "Mine" }, Date.now()));
  const headers = await signedHeaders(secret, "msg_hook_1_1", body);
  expect(headers).toMatchObject({ "content-type": "application/json", "webhook-id": "msg_hook_1_1",
    "webhook-timestamp": "1793800862" });
  expect(new Webhook(secret).verify(body, headers)).toEqual(JSON.parse(body));
  expect(() => new Webhook(secret).verify(body.replace("Mine", "Yours"), headers)).toThrow();
  expect(() => new Webhook(newSecret()).verify(body, headers)).toThrow();
});

it("keeps base64 whole for a recording larger than one piece", () => {
  const bytes = new Uint8Array(0x8000 * 2 + 3).map((_, index) => index % 251);
  expect(base64(bytes)).toBe(Buffer.from(bytes).toString("base64"));
});

it("publishes the schema the format makes", () => {
  if (process.env.RELAY_API_DOC_WRITE) writeFileSync(schemaFile, jsonSchema());
  expect(readFileSync(schemaFile, "utf8"), "The format changed: run `npm run relay:api-doc` in app/").toBe(jsonSchema());
  // note.updated is sent again, for a note changed on its phone, and says so.
  const schema = JSON.parse(jsonSchema()) as { oneOf?: { description?: string; properties: { type: { const: string } } }[];
    anyOf?: { description?: string; properties: { type: { const: string } } }[] };
  const updated = (schema.oneOf ?? schema.anyOf)!.find(item => item.properties.type.const === "note.updated");
  expect(updated?.description).toMatch(/^The phone that sent a note changed/);
  expect(jsonSchema().toLowerCase()).not.toContain("no longer sent");
  expect(jsonSchema().toLowerCase()).not.toContain("pebble");
});

it("publishes a schema that takes a field or a value added later, while the server's own parse stays strict", () => {
  const published = z.fromJSONSchema(JSON.parse(jsonSchema()));
  const built = healthSamples([{ id: 2, ...device, type: "steps", start_at: AT, end_at: AT + 1000, value: 5210, unit: "count", source: "fitness" }], AT);
  const [sample] = (built.data as { samples: Record<string, unknown>[] }).samples;
  const later = { ...built, added: true, data: { samples: [{ ...sample, type: "body_temperature", place: "Home" }] } };
  expect(published.safeParse(later).success).toBe(true);
  expect(() => message.parse(later)).toThrow();
  expect(published.safeParse({ ...built, version: 2 }).success).toBe(false);
  expect(published.safeParse({ ...built, data: { samples: [{ ...sample, value: "many" }] } }).success).toBe(false);
  expect(jsonSchema()).not.toContain('"additionalProperties": false');
  expect(jsonSchema()).not.toContain('"grows"');
});

it("sends a workout with its kind, distance and calories, null when it has none, and no such field on another type", () => {
  const run = { id: 5, ...device, type: "workout" as const, start_at: AT, end_at: AT + 1_920_000, value: 32, unit: "min", source: "watch",
    kind: "running", distance: 5100, calories: 410 };
  const built = healthSamples([run, { ...run, id: 6, kind: null, distance: null, calories: null },
    { id: 7, ...device, type: "steps", start_at: AT, end_at: AT + 1000, value: 10, unit: "count", source: "fitness", kind: null }], AT);
  expect(message.parse(built)).toEqual(built);
  const { samples } = built.data as { samples: Record<string, unknown>[] };
  expect(samples.map(({ kind, distance, calories }) => [kind, distance, calories])).toEqual([["running", 5100, 410], [null, null, null],
    [undefined, undefined, undefined]]);
  expect(samples[2]).not.toHaveProperty("kind");
});

it("sends a night with its times, stage minutes and timeline in ISO 8601, and null times for a bedtime only", () => {
  const stages = [{ stage: "core", start: AT, end: AT + 3_000_000 }, { stage: "deep", start: AT + 3_000_000, end: AT + 6_300_000 }];
  const row = { id: 3, ...device, source: "watch", start_at: AT - 900_000, end_at: AT + 27_000_000, asleep_at: AT, woke_at: AT + 26_700_000,
    asleep: 430, core: 245, deep: 75, rem: 110, awake: 25, stages: JSON.stringify(stages) };
  const built = healthNights([row, { ...row, id: 4, asleep_at: null, woke_at: null, asleep: 0, core: 0, deep: 0, rem: 0, awake: 0, stages: "[]" }], AT);
  expect(message.parse(built)).toEqual(built);
  const { nights } = built.data as { nights: Record<string, unknown>[] };
  expect(nights[0]).toEqual({ id: 3, device: { id: device.device_id, name: "iPad" }, source: "watch", start: "2026-11-04T13:46:02.000Z",
    end: "2026-11-04T21:31:02.000Z", asleep_at: "2026-11-04T14:01:02.000Z", woke_at: "2026-11-04T21:26:02.000Z",
    minutes: { asleep: 430, core: 245, deep: 75, rem: 110, awake: 25 },
    stages: [{ stage: "core", start: "2026-11-04T14:01:02.000Z", end: "2026-11-04T14:51:02.000Z" },
      { stage: "deep", start: "2026-11-04T14:51:02.000Z", end: "2026-11-04T15:46:02.000Z" }] });
  expect(nights[1]).toMatchObject({ asleep_at: null, woke_at: null, stages: [] });
  expect(() => message.parse({ ...built, data: { nights: [{ ...nights[0], stages: [{ stage: "in_bed", start: nights[0].start, end: nights[0].end }] }] } }))
    .toThrow();
});

it("sends calendar events with their status, people and times in ISO 8601", () => {
  const meeting = { id: 7, ...device, event_key: "work:5F1C2B:1793800800000", calendar: "Work", title: "Board meeting", start_at: AT,
    end_at: AT + 3_600_000, all_day: 0, location: "Office, room 2", notes: null, url: null,
    people: '[{"name":"Sam Lee","email":"sam@example.com","organizer":true},{}]', removed_at: null };
  const built = calendarEvents([meeting, { ...meeting, id: 8, all_day: 1, people: "[]", removed_at: AT }], AT);
  expect(message.parse(built)).toEqual(built);
  const { events } = built.data as { events: Record<string, unknown>[] };
  expect(events[0]).toEqual({ id: 7, status: "changed", device: { id: device.device_id, name: "iPad" },
    key: "work:5F1C2B:1793800800000", calendar: "Work", title: "Board meeting", start: "2026-11-04T14:01:02.000Z", end: "2026-11-04T15:01:02.000Z",
    all_day: false, location: "Office, room 2", notes: null, url: null, people: [{ name: "Sam Lee", email: "sam@example.com", organizer: true }, {}] });
  expect(events[1]).toMatchObject({ id: 8, status: "removed", all_day: true, people: [] });
  expect(() => message.parse({ ...built, data: { events: [{ ...events[0], status: "moved" }] } })).toThrow();
});

it("sends a photo with its time and its place, and null for a photo with no place, leaving its bytes for the sender", () => {
  const row = { id: "p0000000-0000-4000-8000-000000000001", ...device, taken_at: Date.UTC(2026, 10, 4, 13, 0), lat: 38.7139, lon: -9.1394,
    width: 1600, height: 1200, bytes: 4 };
  const built = photoCreated(row, AT);
  expect(message.parse(built)).toEqual(built);
  expect(built).toEqual({ version: 1, type: "photo.created", timestamp: "2026-11-04T14:01:02.000Z", data: { photo: {
    id: row.id, device: { id: device.device_id, name: "iPad" }, taken_at: "2026-11-04T13:00:00.000Z", place: { lat: 38.7139, lon: -9.1394 },
    width: 1600, height: 1200, content_type: "image/jpeg", size: 4, base64: "" } } });
  expect(photoCreated({ ...row, lat: null, lon: null }, AT).data).toMatchObject({ photo: { place: null } });
  expect(() => message.parse({ ...built, data: { photo: { ...(built.data as { photo: object }).photo, content_type: "image/png" } } })).toThrow();
});

it("lists a note's files by name, type and size, never their bytes, and leaves the list out of a note with none", () => {
  const pdf = { id: "file-pdf-0001", name: "warranty.pdf", content_type: "application/pdf", size: 245_760 };
  const built = noteCreated(typed, null, AT, [{ ...pdf, file_key: "people/x/attachments/file-pdf-0001" } as typeof pdf]);
  const { note } = built.data as { note: Record<string, unknown> };
  expect(message.parse(built)).toEqual(built);
  expect(note.attachments).toEqual([pdf]);
  expect(JSON.stringify(built)).not.toContain("file_key");
  expect(noteCreated(typed, null, AT).data).not.toHaveProperty("note.attachments");
  expect(() => message.parse({ ...built, data: { note: { ...note, attachments: [{ ...pdf, base64: "AAAA" }] } } })).toThrow();
});

it("sends a changed note with its latest words, the time of the change and its files, each only when it has them", () => {
  const pdf = { id: "file-pdf-0001", name: "warranty.pdf", content_type: "application/pdf", size: 245_760 };
  const edited = noteUpdated({ ...typed, text: "# Desk lamp\n- [x] Receipt", edited_at: AT + 60_000 }, AT + 60_000, [pdf]);
  expect(message.parse(edited)).toEqual(edited);
  expect(edited.data).toMatchObject({ note: { text: "# Desk lamp\n- [x] Receipt", edited_at: "2026-11-04T14:02:02.000Z", attachments: [pdf] } });
  const plain = noteUpdated({ ...typed, edited_at: null }, AT);
  expect(message.parse(plain)).toEqual(plain);
  expect(plain.data).not.toHaveProperty("note.edited_at");
  expect(plain.data).not.toHaveProperty("note.attachments");
  expect(plain.data).not.toHaveProperty("note.audio");
});

it("takes a note's file with its bytes, which the server and the phone both send", () => {
  const file = { version: 1, type: "note.file", timestamp: "2026-11-04T14:01:02.000Z", data: { note_id: typed.id,
    file: { id: "file-pdf-0001", name: "warranty.pdf", content_type: "application/pdf", size: 4, base64: "AAAAGA==" } } };
  expect(message.parse(file)).toEqual(file);
  expect(() => message.parse({ ...file, data: { ...file.data, file: { ...file.data.file, base64: undefined } } })).toThrow();
  expect(Object.keys(format).sort()).toEqual(["calendarEvents", "healthNights", "healthSamples", "jsonSchema", "locationPoints", "locationStays", "message", "noteCreated",
    "noteDeleted", "noteFile", "noteUpdated", "photoCreated", "webhookTest"]);
});

// The phone writes these from mobile/test/webhook_test.dart: one of each message it builds, signed with a fixed secret.
const fixtures = new URL("../../../../../mobile/test/fixtures/webhook/", import.meta.url);

it("takes each message the phone builds, and its signature passes the server's own signing", async () => {
  const names = readdirSync(fixtures).filter(name => name.endsWith(".json")).sort();
  expect(names).toEqual(["calendar.events.json", "health.nights.json", "health.samples.json", "location.points.json", "location.stays.json", "note.created.json", "note.deleted.json",
    "note.file.json", "note.updated.json", "photo.created.json", "webhook.test.json"]);
  for (const name of names) {
    const { secret, headers, body } = JSON.parse(readFileSync(new URL(name, fixtures), "utf8")) as
      { secret: string; headers: Record<string, string>; body: string };
    const parsed = message.parse(JSON.parse(body));
    expect(parsed.type, name).toBe(name.replace(/\.json$/, ""));
    const sent = Number(headers["webhook-timestamp"]) * 1000;
    const server = await signedHeaders(secret, headers["webhook-id"], body, sent);
    expect(headers["webhook-signature"], name).toBe(server["webhook-signature"]);
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(sent);
    expect(new Webhook(secret).verify(body, headers), name).toEqual(JSON.parse(body));
    vi.useRealTimers();
  }
});
