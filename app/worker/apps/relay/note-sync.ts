// GET notes: the notes changed since a phone last asked, by change number, so a phone gets each note once at its newest
// change, and a new phone gets every note. A signed-in person or a phone key reads it. wiki/relay-spaces.md
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asPersonOrPhone } from "./caller.ts";
import { noteChanges } from "./queries.ts";
import { file, place } from "./timeline.ts";

const PAGE = 100;

const syncedNote = z.strictObject({ id: z.string(), clientId: z.string().nullable().describe("The sending device's own id for the note."),
  mine: z.boolean().describe("True when the calling phone sent the note."), source: z.enum(["ring", "typed"]), text: z.string(),
  recordedAt: z.number(), editedAt: z.number().nullable().describe("When the note last changed, in Unix ms; null when never."),
  device: z.string().describe("The name of the device or way in that sent it, such as `Email`."), audio: z.boolean(),
  place: place.nullable(), attachments: z.array(file).describe("The note's files, oldest first.") });

export const noteSync = defineAction({
  operationId: "relay.notes-sync", summary: "Read the notes changed since the last sync",
  description: "Read each note added or changed after a change number, oldest change first. Ask again with `next` while `more` is true.",
  input: z.strictObject({
    since: z.number().int().min(0).optional().describe("The last page's `next`; 0 or left out for every note."),
    limit: z.number().int().min(1).max(PAGE).optional().describe(`How many notes, ${PAGE} when left out.`),
  }),
  output: z.strictObject({ notes: z.array(syncedNote), next: z.number().describe("The change number to ask from next time."),
    more: z.boolean().describe("True when more changes wait after this page.") }),
  encoding: "query", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPersonOrPhone<ActionCall>(async ({ space, caller, call }) => {
    const { since = 0, limit = PAGE } = call.input as { since?: number; limit?: number };
    return Response.json(await noteChanges(space.db, since, limit, caller.device?.id ?? null));
  }),
});
