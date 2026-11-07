// GET summary: one day on the site page: notes, health totals, places visited and calendar events. When two phones,
// or a phone and its watch, count the same steps or sleep, the larger count is the day's.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asPerson } from "./caller.ts";
import { daySummary } from "./queries.ts";
import { MINUTE } from "./store.ts";

const DAY = 24 * 60 * MINUTE;

const output = z.strictObject({
  day: z.string(), notes: z.number(), steps: z.number(), sleepMinutes: z.number(),
  heartRate: z.strictObject({ min: z.number(), max: z.number(), average: z.number() }).nullable(),
  workouts: z.strictObject({ count: z.number(), minutes: z.number() }),
  // The other health values: each only when the day has some.
  weightKg: z.number().optional(), restingHeartRate: z.number().optional(), hrvSdnn: z.number().optional(), hrvRmssd: z.number().optional(),
  bloodOxygen: z.strictObject({ min: z.number(), average: z.number() }).optional(),
  bloodPressure: z.array(z.strictObject({ at: z.number(), upper: z.number(), lower: z.number() })).optional(),
  cycleFlow: z.number().optional(), mindfulMinutes: z.number().optional(), waterMl: z.number().optional(),
  events: z.array(z.strictObject({ title: z.string(), start: z.number(), end: z.number(), allDay: z.boolean(), people: z.array(z.string()) })),
  places: z.array(z.strictObject({ name: z.string(), lat: z.number(), lon: z.number(), from: z.number(), to: z.number() })),
});

export const summary = defineAction({
  operationId: "relay.summary", summary: "Read one day", description: "Count a day's notes, total its health samples, and list its places and calendar events.",
  input: z.strictObject({
    day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(day => !Number.isNaN(Date.parse(day)), "Not a day.").describe("The day, as YYYY-MM-DD."),
    offset: z.number().int().min(-840).max(840).optional().describe("The viewer's time zone, in minutes east of UTC; 0 when left out."),
  }),
  output, encoding: "query", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ space, call }) => {
    const { day: date, offset = 0 } = call.input as { day: string; offset?: number };
    const from = Date.parse(`${date}T00:00:00Z`) - offset * MINUTE;
    return Response.json({ day: date, ...await daySummary(space.db, from, from + DAY) });
  }),
});
