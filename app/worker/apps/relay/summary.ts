// GET summary: one day on the site page: how many notes, the health totals and the places visited. When two phones,
// or a phone and its watch, count the same steps or sleep, the larger count is the day's.
import { z } from "zod";
import { defineAction } from "../../api/contract.ts";
import { MINUTE, session, type Db } from "./store.ts";

const DAY = 24 * 60 * MINUTE;

const output = z.strictObject({
  day: z.string(), notes: z.number(), steps: z.number(), sleepMinutes: z.number(),
  heartRate: z.strictObject({ min: z.number(), max: z.number(), average: z.number() }).nullable(),
  workouts: z.strictObject({ count: z.number(), minutes: z.number() }),
  places: z.array(z.strictObject({ name: z.string(), lat: z.number(), lon: z.number(), from: z.number(), to: z.number() })),
});

const one = <Row>(db: Db, sql: string, from: number, to: number) => db.prepare(sql).bind(from, to).first<Row>();

/** Per device and source, then the largest: a phone and its watch that both count the day's steps don't double them. */
const largest = (type: string, total: string, at: string) => `SELECT COALESCE(MAX(total), 0) AS total FROM
  (SELECT ${total} AS total FROM relay_health WHERE type = '${type}' AND ${at} >= ? AND ${at} < ? GROUP BY device_id, source)`;

async function day(db: Db, from: number, to: number) {
  const [notes, steps, sleep, heart, workouts, places] = await Promise.all([
    one<{ count: number }>(db, "SELECT COUNT(*) AS count FROM relay_notes WHERE recorded_at >= ? AND recorded_at < ?", from, to),
    one<{ total: number }>(db, largest("steps", "SUM(value)", "start_at"), from, to),
    one<{ total: number }>(db, largest("sleep", `SUM(end_at - start_at) / ${MINUTE}`, "end_at"), from, to),
    one<{ min: number | null; max: number; average: number }>(db, `SELECT MIN(value) AS min, MAX(value) AS max, ROUND(AVG(value)) AS average
      FROM relay_health WHERE type = 'heart_rate' AND start_at >= ? AND start_at < ?`, from, to),
    one<{ count: number; minutes: number }>(db, `SELECT COUNT(*) AS count, COALESCE(SUM(end_at - start_at), 0) / ${MINUTE} AS minutes
      FROM relay_health WHERE type = 'workout' AND start_at >= ? AND start_at < ?`, from, to),
    db.prepare(`SELECT COALESCE(place, printf('%.3f, %.3f', lat, lon)) AS name, AVG(lat) AS lat, AVG(lon) AS lon, MIN(at) AS "from", MAX(at) AS "to"
      FROM relay_locations WHERE at >= ? AND at < ? GROUP BY 1 ORDER BY 4`).bind(from, to).all<{ name: string; lat: number; lon: number; from: number; to: number }>(),
  ]);
  return { notes: notes!.count, steps: Math.round(steps!.total), sleepMinutes: Math.round(sleep!.total),
    heartRate: heart!.min === null ? null : { min: heart!.min, max: heart!.max, average: heart!.average },
    workouts: { count: workouts!.count, minutes: Math.round(workouts!.minutes) }, places: places.results };
}

export const summary = defineAction({
  operationId: "relay.summary", summary: "Read one day", description: "Count a day's notes, total its health samples and list its places.",
  input: z.strictObject({
    day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(day => !Number.isNaN(Date.parse(day)), "Not a day.").describe("The day, as YYYY-MM-DD."),
    offset: z.number().int().min(-840).max(840).optional().describe("The viewer's time zone, in minutes east of UTC; 0 when left out."),
  }),
  output, encoding: "query", effect: "read", agentAvailable: false, errors: {}, examples: [],
  async handler(_request, env, { input }) {
    const { day: date, offset = 0 } = input as { day: string; offset?: number };
    const from = Date.parse(`${date}T00:00:00Z`) - offset * MINUTE;
    return Response.json({ day: date, ...await day(session(env), from, from + DAY) });
  },
});
