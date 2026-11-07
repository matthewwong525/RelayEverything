// POST health and POST locations: a phone's batch of health samples or location points, each stored once per device,
// however often the phone sends it. Both answer how many rows were new.
import { z } from "zod";
import { defineAction, type Action, type ActionCall } from "../../api/contract.ts";
import { asDevice } from "./caller.ts";
import { HEALTH_TYPES } from "./queries.ts";
import { accuracy, BATCH, insertNew, latitude, longitude, placeName, time, type Db } from "./store.ts";
import { wake, type Kind } from "./webhooks/send.ts";

const sample = z.strictObject({
  type: z.enum(HEALTH_TYPES), start: time, end: time,
  value: z.number().min(0).max(1e9), unit: z.string().min(1).max(20), source: z.string().min(1).max(200),
}).refine(item => item.end >= item.start, "end comes before start.");
const point = z.strictObject({ at: time, lat: latitude, lon: longitude, accuracy, place: placeName.optional() });
const output = z.strictObject({ received: z.number().int(), added: z.number().int() });
const limits = { inputBytes: 262_144, outputBytes: 1024, timeoutMs: 15_000 };

/** One batch route: check the caller is a device, store the new rows, then wake the webhooks that take this kind
 *  when any row was new. */
function batch<Item>(name: string, kind: Kind, items: z.ZodType<Item[]>, description: string,
  save: (db: Db, device: string, rows: Item[]) => Promise<number>): Action {
  return defineAction({
    operationId: `relay.${name}-add`, summary: `Store a phone's ${name}`, description,
    input: z.strictObject({ [name]: items.describe(`Up to ${BATCH} rows; a row stored before is skipped.`) }),
    output, encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [], limits,
    handler: asDevice<ActionCall>("Only a Relay Everything device key can send this", async ({ space, device, env, call }) => {
      const rows = (call.input as Record<string, Item[]>)[name];
      const added = await save(space.db, device.id, rows);
      await wake(env, space, added ? [kind] : []);
      return Response.json({ received: rows.length, added });
    }),
  });
}

const field = (name: string) => `json_extract(value, '$.${name}')`;

export const health = batch("samples", "health", z.array(sample).min(1).max(BATCH),
  "Store health samples from Apple Health or Health Connect, such as steps, sleep, weight and blood pressure, once per type, time span and source.",
  (db, device, rows) => insertNew(db, `INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at)
    SELECT ?, ${["type", "start", "end", "value", "unit", "source"].map(field).join(", ")}, ? FROM json_each(?) WHERE true
    ON CONFLICT (device_id, type, start_at, end_at, source) DO NOTHING RETURNING id`, device, Date.now(), JSON.stringify(rows)));

export const locations = batch("points", "locations", z.array(point).min(1).max(BATCH),
  "Store the phone's location history, once per time. A note keeps the place it came with: a point gives no note a place.",
  (db, device, rows) => insertNew(db, `INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, place, created_at)
    SELECT ?, ${["at", "lat", "lon", "accuracy", "place"].map(field).join(", ")}, ? FROM json_each(?) WHERE true
    ON CONFLICT (device_id, at) DO NOTHING RETURNING id`, device, Date.now(), JSON.stringify(rows)));
