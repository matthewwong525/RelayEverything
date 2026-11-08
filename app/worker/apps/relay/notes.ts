// POST notes: a note typed on a phone, with its place and its files' names; each file's bytes come after, by POST
// attachments. A phone that sends it again, after losing its answer, gets the same note back: add-note.ts.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { addNote } from "./add-note.ts";
import { asDevice } from "./caller.ts";
import { accuracy, latitude, longitude, placeName, time } from "./store.ts";

/** A note holds up to 10 files, each up to 25 MB. */
export const MAX_FILES = 10;
export const MAX_FILE_BYTES = 25 * 1024 * 1024;
/** The phone's own id for a note or a file. */
export const CLIENT_ID = /^[A-Za-z0-9-]{8,64}$/;

const attachment = z.strictObject({
  id: z.string().regex(CLIENT_ID).describe("The phone's own id for the file: its upload names it."),
  name: z.string().min(1).max(255).describe("The file's name, such as `warranty.pdf`."),
  type: z.string().max(255).describe("The file's content type, such as `application/pdf`; empty when the phone does not know it."),
  size: z.number().int().min(0).max(MAX_FILE_BYTES).describe("The file's size in bytes, up to 25 MB."),
});

/** A note's files, up to 10, each with its own id. */
export const noteFiles = z.array(attachment).max(MAX_FILES)
  .refine(files => new Set(files.map(file => file.id)).size === files.length, "Give each file its own id.");
export const noteText = z.string().max(20_000).describe("What the note says. It can be empty only when the note has files.");
export const hasWords = (note: { text: string; attachments?: unknown[] }) => note.text.trim() !== "" || !!note.attachments?.length;

const MIME = /^[\w.+-]+\/[\w.+-]+$/;
/** A file whose type the phone does not know, or sent in a shape no header holds, is kept as plain bytes. */
export const typeOf = (type: string) => MIME.test(type.trim()) ? type.trim().toLowerCase() : "application/octet-stream";
export const withTypes = (files?: z.infer<typeof noteFiles>) => files?.map(file => ({ ...file, type: typeOf(file.type) }));

const noteInput = z.strictObject({
  clientId: z.string().regex(CLIENT_ID).describe("The phone's own id for the note, so a resend is stored once."),
  text: noteText,
  createdAt: time.describe("When it was written, in Unix milliseconds."),
  lat: latitude.optional().describe("Where it was written: latitude. Send it with lon."),
  lon: longitude.optional().describe("Where it was written: longitude. Send it with lat."),
  accuracy: accuracy.optional().describe("How sure the phone was of the place, in meters."),
  place: placeName.optional().describe("The place's name from the phone's address lookup."),
  attachments: noteFiles.optional()
    .describe("The note's files, up to 10: only their names, types and sizes. Send each file's bytes after, with POST attachments."),
}).refine(note => (note.lat === undefined) === (note.lon === undefined), "Send lat and lon together.")
  .refine(hasWords, "Give the note words or a file.");

export const notes = defineAction({
  operationId: "relay.notes-add", summary: "Store a typed note", description: "Store a note typed on a Relay Everything phone, once per phone and clientId.",
  input: noteInput, output: z.strictObject({ id: z.string(), added: z.boolean() }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asDevice<ActionCall>("Only a Relay Everything device key can send notes", async ({ space, device, env, call }) => {
    const note = call.input as z.infer<typeof noteInput>;
    return Response.json(await addNote(env, space, device.id, { ...note, attachments: withTypes(note.attachments) }));
  }),
});
