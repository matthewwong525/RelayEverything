// POST notes: a note typed on a phone, with the place the phone had. A phone that sends it again, after losing
// its answer, gets the same note back: add-note.ts.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { addNote } from "./add-note.ts";
import { asDevice } from "./caller.ts";
import { accuracy, latitude, longitude, placeName, time } from "./store.ts";

const noteInput = z.strictObject({
  clientId: z.string().regex(/^[A-Za-z0-9-]{8,64}$/).describe("The phone's own id for the note, so a resend is stored once."),
  text: z.string().min(1).max(20_000).describe("What the note says."),
  createdAt: time.describe("When it was written, in Unix milliseconds."),
  lat: latitude.optional().describe("Where it was written: latitude. Send it with lon."),
  lon: longitude.optional().describe("Where it was written: longitude. Send it with lat."),
  accuracy: accuracy.optional().describe("How sure the phone was of the place, in meters."),
  place: placeName.optional().describe("The place's name from the phone's address lookup."),
}).refine(note => (note.lat === undefined) === (note.lon === undefined), "Send lat and lon together.");

export const notes = defineAction({
  operationId: "relay.notes-add", summary: "Store a typed note", description: "Store a note typed on a Relay Everything phone, once per phone and clientId.",
  input: noteInput, output: z.strictObject({ id: z.string(), added: z.boolean() }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asDevice<ActionCall>("Only a Relay Everything device key can send notes", async ({ space, device, env, call }) =>
    Response.json(await addNote(env, space, device.id, call.input as z.infer<typeof noteInput>))),
});
