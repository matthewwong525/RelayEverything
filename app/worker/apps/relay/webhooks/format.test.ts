import { readFileSync, writeFileSync } from "node:fs";
import { Webhook } from "standardwebhooks";
import { afterEach, expect, it, vi } from "vitest";
import { calendarEvents, healthSamples, jsonSchema, locationPoints, message, noteCreated, noteUpdated, webhookTest, type NoteRow } from "./format.ts";
import { base64, newSecret, signedHeaders } from "./sign.ts";

const schemaFile = new URL("../../../../../site/public/webhooks/v1.schema.json", import.meta.url);
const AT = Date.UTC(2026, 10, 4, 14, 1, 2);
const device = { device_id: "d0000000-0000-4000-8000-000000000002", device_name: "Pebble app" };
const ring: NoteRow = { id: "a0000000-0000-4000-8000-000000000001", source: "ring", text: "Call the PCB fab about the second batch.",
  recorded_at: Date.UTC(2026, 10, 4, 14, 1), created_at: AT, ...device, lat: 43.6629, lon: -79.3957, accuracy: 15, place: "Harbord St",
  place_from: "history", audio_key: "notes/a0000000-0000-4000-8000-000000000001.m4a" };
const typed: NoteRow = { ...ring, id: "a0000000-0000-4000-8000-000000000002", source: "typed", lat: null, lon: null, accuracy: null,
  place: null, place_from: null, audio_key: null };

it("builds each type in the published format, with times in ISO 8601 and a recording in base64", () => {
  const built = [
    noteCreated(ring, base64(new Uint8Array([0, 0, 0, 24])), AT), noteCreated(typed, null, AT), noteUpdated(ring, AT),
    healthSamples([{ id: 2, ...device, type: "steps", start_at: AT, end_at: AT + 1000, value: 5210, unit: "count", source: "fitness" }], AT),
    locationPoints([{ id: 1, ...device, at: AT, lat: 43.6629, lon: -79.3957, accuracy: 15, place: null }], AT),
    webhookTest({ id: "e0000000-0000-4000-8000-000000000001", name: "Example database" }, AT),
  ];
  for (const item of built) expect(message.parse(item), item.type).toEqual(item);
  expect(built[0]).toEqual({ version: 1, type: "note.created", timestamp: "2026-11-04T14:01:02.000Z", data: { note: {
    id: ring.id, source: "ring", text: ring.text, recorded_at: "2026-11-04T14:01:00.000Z", created_at: "2026-11-04T14:01:02.000Z",
    device: { id: device.device_id, name: "Pebble app" }, place: { lat: 43.6629, lon: -79.3957, accuracy: 15, name: "Harbord St", from: "history" },
    audio: { content_type: "audio/mp4", base64: "AAAAGA==" } } } });
  expect(built[1].data).toMatchObject({ note: { place: null, audio: null } });
  expect(built[2].data).not.toHaveProperty("note.audio");
  expect(built[3].data).toEqual({ samples: [{ id: 2, device: { id: device.device_id, name: "Pebble app" }, type: "steps",
    start: "2026-11-04T14:01:02.000Z", end: "2026-11-04T14:01:03.000Z", value: 5210, unit: "count", source: "fitness" }] });
  expect(() => message.parse({ ...built[5], version: 2 })).toThrow();
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
});

it("sends calendar events with their status, people and times in ISO 8601", () => {
  const meeting = { id: 7, ...device, event_key: "work:5F1C2B:1793800800000", calendar: "Work", title: "Board meeting", start_at: AT,
    end_at: AT + 3_600_000, all_day: 0, location: "Office, room 2", notes: null, url: null,
    people: '[{"name":"Sam Lee","email":"sam@example.com","organizer":true},{}]', removed_at: null };
  const built = calendarEvents([meeting, { ...meeting, id: 8, all_day: 1, people: "[]", removed_at: AT }], AT);
  expect(message.parse(built)).toEqual(built);
  const { events } = built.data as { events: Record<string, unknown>[] };
  expect(events[0]).toEqual({ id: 7, status: "changed", device: { id: device.device_id, name: "Pebble app" },
    key: "work:5F1C2B:1793800800000", calendar: "Work", title: "Board meeting", start: "2026-11-04T14:01:02.000Z", end: "2026-11-04T15:01:02.000Z",
    all_day: false, location: "Office, room 2", notes: null, url: null, people: [{ name: "Sam Lee", email: "sam@example.com", organizer: true }, {}] });
  expect(events[1]).toMatchObject({ id: 8, status: "removed", all_day: true, people: [] });
  expect(() => message.parse({ ...built, data: { events: [{ ...events[0], status: "moved" }] } })).toThrow();
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
