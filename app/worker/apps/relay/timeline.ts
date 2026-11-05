// GET timeline: every note, newest first, with its place, a page at a time. Phones and the site page read it.
import { z } from "zod";
import { defineAction } from "../../api/contract.ts";
import { session, time } from "./store.ts";

const PAGE = 50;

const place = z.strictObject({ lat: z.number(), lon: z.number(), accuracy: z.number().nullable(), name: z.string().nullable(),
  from: z.enum(["phone", "history"]) });
const timelineNote = z.strictObject({ id: z.string(), source: z.enum(["ring", "typed"]), text: z.string(), recordedAt: z.number(),
  device: z.string(), audio: z.boolean(), place: place.nullable() });

// lat, lon and place_from are set together: notes.ts takes lat and lon as a pair, and place.ts copies all three.
type Row = { id: string; source: "ring" | "typed"; text: string; recorded_at: number; device: string; audio: number;
  lat: number | null; lon: number | null; accuracy: number | null; place: string | null; place_from: "phone" | "history" | null };

const shaped = (row: Row) => ({ id: row.id, source: row.source, text: row.text, recordedAt: row.recorded_at, device: row.device,
  audio: row.audio === 1, place: row.lat === null ? null :
    { lat: row.lat, lon: row.lon!, accuracy: row.accuracy, name: row.place, from: row.place_from! } });

export const timeline = defineAction({
  operationId: "relay.timeline", summary: "Read the notes", description: "Read Relay's notes, newest first, with each one's place.",
  input: z.strictObject({
    before: time.optional().describe("Only notes recorded before this Unix time in milliseconds: the last page's `next`."),
    beforeId: z.string().max(64).optional().describe("With `before`, also the notes at that time with a lower id: the last page's `nextId`."),
    limit: z.number().int().min(1).max(100).optional().describe(`How many notes, ${PAGE} when left out.`),
  }),
  output: z.strictObject({ notes: z.array(timelineNote), next: z.number().nullable(), nextId: z.string().nullable() }),
  encoding: "query", effect: "read", agentAvailable: false, errors: {}, examples: [],
  async handler(_request, env, { input }) {
    const { before = Number.MAX_SAFE_INTEGER, beforeId = "", limit = PAGE } = input as { before?: number; beforeId?: string; limit?: number };
    const { results } = await session(env).prepare(`SELECT n.id, n.source, n.text, n.recorded_at, d.name AS device,
        n.audio_key IS NOT NULL AS audio, n.lat, n.lon, n.accuracy, n.place, n.place_from
      FROM relay_notes n JOIN relay_devices d ON d.id = n.device_id
      WHERE n.recorded_at < ? OR (n.recorded_at = ? AND n.id < ?)
      ORDER BY n.recorded_at DESC, n.id DESC LIMIT ?`).bind(before, before, beforeId, limit + 1).all<Row>();
    const page = results.slice(0, limit);
    // Two notes can share a time, so a page ends at a time and an id: the next page starts just after both.
    const last = results.length > limit ? page.at(-1)! : null;
    return Response.json({ notes: page.map(shaped), next: last?.recorded_at ?? null, nextId: last?.id ?? null });
  },
});
