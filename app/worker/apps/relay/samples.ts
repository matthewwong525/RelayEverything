// POST health and POST locations: a phone's batch of health samples or location points, each stored once per device,
// however often the phone sends it. Both answer how many rows were new.
import { z } from "zod";
import { defineAction, type Action, type ActionCall } from "../../api/contract.ts";
import { asDevice } from "./caller.ts";
import type { KindId } from "./kinds.ts";
import { HEALTH_TYPES } from "./queries.ts";
import { accuracy, BATCH, insertNew, latitude, longitude, placeName, time, type Db } from "./store.ts";
import { wake } from "./webhooks/send.ts";

const amount = z.number().min(0).max(1e6);
const sample = z.strictObject({
  type: z.enum(HEALTH_TYPES), start: time, end: time,
  value: z.number().min(0).max(1e9), unit: z.string().min(1).max(20), source: z.string().min(1).max(200),
  kind: z.string().min(1).max(60).optional().describe("A workout's kind, such as running."),
  distance: amount.optional().describe("A workout's distance, in meters."),
  calories: amount.optional().describe("A workout's calories, in kcal."),
}).refine(item => item.end >= item.start, "end comes before start.")
  .refine(item => item.type === "workout" || [item.kind, item.distance, item.calories].every(value => value === undefined),
    "Only a workout has a kind, distance or calories.");
const point = z.strictObject({ at: time, lat: latitude, lon: longitude, accuracy, place: placeName.optional() });
const output = z.strictObject({ received: z.number().int(), added: z.number().int() });
const limits = { inputBytes: 262_144, outputBytes: 1024, timeoutMs: 15_000 };

/** How many rows were new, and how many rows were new or changed: a changed row wakes the webhooks too. */
type Saved = { added: number; changed: number };
const counted = (added: number): Saved => ({ added, changed: added });

/** One batch route: check the caller is a device, store the new rows, then wake the webhooks that take this kind
 *  when any row was new or changed. */
function batch<Item>(name: string, kind: KindId, items: z.ZodType<Item[]>, description: string,
  save: (db: Db, device: string, rows: Item[]) => Promise<Saved>): Action {
  return defineAction({
    operationId: `relay.${name}-add`, summary: `Store a phone's ${name}`, description,
    input: z.strictObject({ [name]: items.describe(`Up to ${BATCH} rows; a row stored before is skipped.`) }),
    output, encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [], limits,
    handler: asDevice<ActionCall>("Only a Relay Everything device key can send this", async ({ space, device, env, call }) => {
      const rows = (call.input as Record<string, Item[]>)[name];
      const { added, changed } = await save(space.db, device.id, rows);
      await wake(env, space, changed ? [kind] : []);
      return Response.json({ received: rows.length, added });
    }),
  });
}

const field = (name: string) => `json_extract(value, '$.${name}')`;

/** Fills a workout's details on a row that has none, once, then stores the new samples: a filled row is logged by its
 *  trigger, so it wakes the webhooks, but counts as no new row. */
async function saveSamples(db: Db, device: string, rows: unknown[]): Promise<Saved> {
  const json = JSON.stringify(rows);
  const { results: filled } = await db.prepare(`UPDATE relay_health AS h SET kind = s.kind, distance = s.distance, calories = s.calories
    FROM (SELECT ${["type", "start", "end", "source", "kind", "distance", "calories"].map(name => `${field(name)} AS "${name}"`).join(", ")}
      FROM json_each(?2)) AS s
    WHERE h.device_id = ?1 AND h.kind IS NULL AND s.kind IS NOT NULL AND h.type = s.type AND h.start_at = s.start AND h.end_at = s."end"
      AND h.source = s.source RETURNING id`).bind(device, json).all();
  const added = await insertNew(db, `INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, kind, distance,
      calories, created_at)
    SELECT ?, ${["type", "start", "end", "value", "unit", "source", "kind", "distance", "calories"].map(field).join(", ")}, ?
    FROM json_each(?) WHERE true ON CONFLICT (device_id, type, start_at, end_at, source) DO NOTHING RETURNING id`, device, Date.now(), json);
  return { added, changed: added + filled.length };
}

export const health = batch("samples", "health", z.array(sample).min(1).max(BATCH),
  "Store health samples from Apple Health or Health Connect, such as steps, sleep, weight and blood pressure, once per type, time span and source. A workout sent again with its kind, distance and calories fills them on a row that has none.",
  saveSamples);

export const locations = batch("points", "locations", z.array(point).min(1).max(BATCH),
  "Store the phone's location history, once per time. A note keeps no place: a place sent with a note becomes one point at the note's time.",
  async (db, device, rows) => counted(await insertNew(db, `INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, place, created_at)
    SELECT ?, ${["at", "lat", "lon", "accuracy", "place"].map(field).join(", ")}, ? FROM json_each(?) WHERE true
    ON CONFLICT (device_id, at) DO NOTHING RETURNING id`, device, Date.now(), JSON.stringify(rows))));
