// Format v1 of what a webhook receives: one envelope, eight types; mobile/lib/data/webhook.dart builds it too. The
// source of the public site/public/webhooks/v1.schema.json, which takes fields and values it does not list.
import { z } from "zod";
import { HEALTH_TYPES, type HealthType } from "../queries.ts";

/** A list of values that can get a new one: the schema publishes it as text, with the values known today. */
const GROWS = { grows: true };
const iso = z.iso.datetime().describe("A time in ISO 8601, UTC.");
const device = z.strictObject({
  id: z.string().describe("The device key's id in Relay Everything, or the phone's own install id when the phone sends to its own webhook."),
  name: z.string() })
  .describe("The phone or other device that sent the item.");
const place = z.strictObject({
  lat: z.number(), lon: z.number(), accuracy: z.number().nullable().describe("In meters."),
  name: z.string().nullable().describe("The place's name from the phone's address lookup, such as a street."),
  from: z.enum(["phone", "history"]).describe("phone: where a typed note was written. history: the location point nearest a ring note."),
});
const note = z.strictObject({
  id: z.string().describe("The note's id, the same in every message about this note: a UUID, or the phone's own note id when the phone sends to its own webhook."),
  source: z.enum(["ring", "typed"]), text: z.string().describe("The words: a typed note, or a ring note's transcription."),
  recorded_at: iso, created_at: iso.describe("When Relay Everything stored it."), device, place: place.nullable(),
});
const audio = z.strictObject({ content_type: z.literal("audio/mp4"), base64: z.string() }).nullable()
  .describe("A ring note's recording, or null for a typed note or a ring note with words only.");
const attachment = z.strictObject({
  id: z.string().describe("The file's id, from the phone that sent it."), name: z.string().describe("The file's name, such as warranty.pdf."),
  content_type: z.string().describe("Such as application/pdf."), size: z.number().int().min(0).describe("In bytes."),
});
const attachments = z.array(attachment).min(1).max(10).optional()
  .describe("The note's files: each one's name, type and size, never its bytes. Only a note with files has this list.");
const ownId = "Unique in this Relay Everything server, or on the phone when the phone sends to its own webhook.";
const sample = z.strictObject({
  id: z.number().int().describe(ownId), device, type: z.enum(HEALTH_TYPES).meta(GROWS),
  start: iso, end: iso, value: z.number(), unit: z.string(), source: z.string().describe("The app or watch that counted it."),
});
const point = z.strictObject({
  id: z.number().int().describe(ownId), device, at: iso, lat: z.number(), lon: z.number(),
  accuracy: z.number().describe("In meters."), place: z.string().nullable(),
});
const event = z.strictObject({
  id: z.number().int().describe("Unique in this Relay Everything server, or made from the phone's install id and the key when the phone sends to its own webhook: upsert by it."),
  status: z.enum(["changed", "removed"]).meta(GROWS).describe("changed: new or changed. removed: deleted on the phone, or its calendar turned off."),
  device, key: z.string().describe("The phone's key for this occurrence: each time of a repeating event has its own."),
  calendar: z.string().nullable().describe("The calendar's name."), title: z.string().nullable(), start: iso, end: iso, all_day: z.boolean(),
  location: z.string().nullable(), notes: z.string().nullable(), url: z.string().nullable(),
  people: z.array(z.strictObject({ name: z.string().optional(), email: z.string().optional(), organizer: z.boolean().optional() })),
});

const photo = z.strictObject({
  id: z.string().describe("The photo's id: a UUID, or the phone's own photo id when the phone sends to its own webhook."),
  device, taken_at: iso.describe("When the photo was taken, by the phone's photo library."),
  place: z.strictObject({ lat: z.number(), lon: z.number() }).nullable().describe("Where the photo was taken, or null for a photo with no place."),
  width: z.number().int().min(1).describe("In pixels: at most 1,600 on the long side."), height: z.number().int().min(1).describe("In pixels."),
  content_type: z.literal("image/jpeg"), size: z.number().int().min(0).describe("The JPEG's size in bytes, up to 3 MB."),
  base64: z.string().describe("The JPEG's bytes in base64."),
});

const BATCH = 500;
const stored = iso.describe("When Relay Everything, or the phone that sends to its own webhook, stored what this message holds.");
const envelope = <Type extends string, Data extends z.ZodType>(type: Type, data: Data, description: string) =>
  z.strictObject({ version: z.literal(1), type: z.literal(type), timestamp: stored, data }).describe(description);

export const message = z.discriminatedUnion("type", [
  envelope("note.created", z.strictObject({ note: note.extend({ audio, attachments }) }), "A note reached Relay Everything."),
  envelope("note.updated", z.strictObject({ note }), "No longer sent: the server gives no note a place later. It once said a ring note got its place from a later location batch. It has no audio."),
  envelope("health.samples", z.strictObject({ samples: z.array(sample).min(1).max(BATCH) }), "Health samples, in the order Relay Everything stored them."),
  envelope("location.points", z.strictObject({ points: z.array(point).min(1).max(BATCH) }), "Location points, in the order Relay Everything stored them."),
  envelope("note.file", z.strictObject({ note_id: z.string().describe("The id of the note this file is on."),
    file: attachment.extend({ base64: z.string().describe("The file's bytes in base64.") }) }),
    "One file of a note, with its bytes. Only a phone that sends to its own webhook sends it, after the note's note.created."),
  envelope("calendar.events", z.strictObject({ events: z.array(event).min(1).max(BATCH) }),
    "Calendar events that are new, changed or removed, in the order Relay Everything stored them. A removed event from a phone that sends to its own webhook has only its key, id and start."),
  envelope("photo.created", z.strictObject({ photo }),
    "A new photo from the Photos switch, with its bytes. A photo shared into a note goes as one of the note's files instead."),
  envelope("webhook.test", z.strictObject({ webhook: z.strictObject({ id: z.string(), name: z.string() }) }), "Send a test, from the Relay Everything page or the phone."),
]).meta({ title: "Relay Everything webhook message, version 1", description: "The JSON body of each message a Relay Everything webhook sends." });

type Message = z.infer<typeof message>;

/** Each row as Relay's tables hold it, with its device's name. */
export type NoteRow = { id: string; source: "ring" | "typed"; text: string; recorded_at: number; created_at: number; device_id: string;
  device_name: string; lat: number | null; lon: number | null; accuracy: number | null; place: string | null;
  place_from: "phone" | "history" | null; audio_key: string | null };
export type AttachmentRow = { id: string; name: string; content_type: string; size: number };
export type HealthRow = { id: number; device_id: string; device_name: string; type: HealthType;
  start_at: number; end_at: number; value: number; unit: string; source: string };
export type LocationRow = { id: number; device_id: string; device_name: string; at: number; lat: number; lon: number; accuracy: number;
  place: string | null };
export type EventRow = { id: number; device_id: string; device_name: string; event_key: string; calendar: string | null;
  title: string | null; start_at: number; end_at: number; all_day: number; location: string | null; notes: string | null; url: string | null;
  people: string; removed_at: number | null };

export type PhotoRow = { id: string; device_id: string; device_name: string; taken_at: number; lat: number | null; lon: number | null;
  width: number; height: number; bytes: number };

const isoOf = (ms: number) => new Date(ms).toISOString();
const deviceOf = (row: { device_id: string; device_name: string }) => ({ id: row.device_id, name: row.device_name });

// lat, lon and place_from are stored together: the first version's migration checks it.
const noteOf = (row: NoteRow) => ({ id: row.id, source: row.source, text: row.text, recorded_at: isoOf(row.recorded_at),
  created_at: isoOf(row.created_at), device: deviceOf(row), place: row.lat === null ? null :
    { lat: row.lat, lon: row.lon!, accuracy: row.accuracy, name: row.place, from: row.place_from! } });

const wrap = <Built extends Message>(type: Built["type"], data: Built["data"], at: number) =>
  ({ version: 1, type, timestamp: isoOf(at), data }) as Built;

/** A new note; `audio` is its recording in base64, or null. `files` are listed only when there are some. */
export const noteCreated = (row: NoteRow, audio: string | null, at: number, files: AttachmentRow[] = []) =>
  wrap("note.created", { note: { ...noteOf(row), audio: audio === null ? null : { content_type: "audio/mp4", base64: audio },
    ...files.length ? { attachments: files.map(({ id, name, content_type, size }) => ({ id, name, content_type, size })) } : {} } }, at);

export const noteUpdated = (row: NoteRow, at: number) => wrap("note.updated", { note: noteOf(row) }, at);

export const healthSamples = (rows: HealthRow[], at: number) => wrap("health.samples", { samples: rows.map(row => ({
  id: row.id, device: deviceOf(row), type: row.type, start: isoOf(row.start_at), end: isoOf(row.end_at), value: row.value,
  unit: row.unit, source: row.source })) }, at);

export const locationPoints = (rows: LocationRow[], at: number) => wrap("location.points", { points: rows.map(row => ({
  id: row.id, device: deviceOf(row), at: isoOf(row.at), lat: row.lat, lon: row.lon, accuracy: row.accuracy, place: row.place })) }, at);

export const calendarEvents = (rows: EventRow[], at: number) => wrap("calendar.events", { events: rows.map(row => ({
  id: row.id, status: row.removed_at === null ? "changed" as const : "removed" as const, device: deviceOf(row), key: row.event_key,
  calendar: row.calendar, title: row.title, start: isoOf(row.start_at), end: isoOf(row.end_at), all_day: row.all_day === 1,
  location: row.location, notes: row.notes, url: row.url, people: JSON.parse(row.people) })) }, at);

/** A new photo; `jpeg` is its bytes in base64. lat and lon are stored together: POST photos checks it. */
export const photoCreated = (row: PhotoRow, jpeg: string, at: number) => wrap("photo.created", { photo: { id: row.id, device: deviceOf(row),
  taken_at: isoOf(row.taken_at), place: row.lat === null ? null : { lat: row.lat, lon: row.lon! }, width: row.width, height: row.height,
  content_type: "image/jpeg", size: row.bytes, base64: jpeg } }, at);

export const webhookTest = (webhook: { id: string; name: string }, at: number) => wrap("webhook.test", { webhook }, at);

/** Makes the published schema take a field or a value it does not list. The server's own parse stays strict. */
function lenient({ jsonSchema: schema }: { jsonSchema: Record<string, unknown> }) {
  if (schema.additionalProperties === false) delete schema.additionalProperties;
  if (!schema.grows) return;
  schema.examples = schema.enum;
  delete schema.enum;
  delete schema.grows;
}

/** The public JSON Schema, as site/public/webhooks/v1.schema.json holds it. */
export const jsonSchema = () => `${JSON.stringify(z.toJSONSchema(message, { override: lenient }), null, 2)}\n`;
