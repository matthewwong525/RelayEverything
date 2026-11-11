// GET timeline: every note, newest first, a page at a time. Phones and the site page read it.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { notePage } from "./queries.ts";
import { asPerson } from "./caller.ts";
import { time } from "./store.ts";

const PAGE = 50;

export const file = z.strictObject({ id: z.string(), name: z.string(), type: z.string(), size: z.number(),
  ready: z.boolean().describe("True once the phone has sent the file: then GET attachment opens it.") });
const timelineNote = z.strictObject({ id: z.string(), source: z.enum(["ring", "typed"]), text: z.string(), recordedAt: z.number(),
  device: z.string(), audio: z.boolean(), attachments: z.array(file).describe("The note's files, oldest first.") });

export const timeline = defineAction({
  operationId: "relay.timeline", summary: "Read the notes", description: "Read Relay Everything's notes, newest first. A note has no place: read places by its time.",
  input: z.strictObject({
    before: time.optional().describe("Only notes recorded before this Unix time in milliseconds: the last page's `next`."),
    beforeId: z.string().max(64).optional().describe("With `before`, also the notes at that time with a lower id: the last page's `nextId`."),
    limit: z.number().int().min(1).max(100).optional().describe(`How many notes, ${PAGE} when left out.`),
  }),
  output: z.strictObject({ notes: z.array(timelineNote), next: z.number().nullable(), nextId: z.string().nullable() }),
  encoding: "query", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ space, call }) => {
    const { before, beforeId, limit = PAGE } = call.input as { before?: number; beforeId?: string; limit?: number };
    return Response.json(await notePage(space.db, { before, beforeId, limit }));
  }),
});
