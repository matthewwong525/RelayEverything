// POST health and POST locations: a phone's batch of health samples or location points, each stored once per device,
// however often the phone sends it. Both answer how many rows were new.
import { z } from "zod";
import { defineAction, type Action } from "../../api/contract.ts";
import { deviceOf } from "./device.ts";
import { placeRingNotes } from "./place.ts";
import { accuracy, BATCH, insertNew, latitude, longitude, placeName, refused, session, time, type Db } from "./store.ts";
import { wake, type Kind } from "./webhooks/send.ts";

const sample = z.strictObject({
  type: z.enum(["steps", "heart_rate", "sleep", "workout"]), start: time, end: time,
  value: z.number().min(0).max(1e9), unit: z.string().min(1).max(20), source: z.string().min(1).max(200),
}).refine(item => item.end >= item.start, "end comes before start.");
const point = z.strictObject({ at: time, lat: latitude, lon: longitude, accuracy, place: placeName.optional() });
const output = z.strictObject({ received: z.number().int(), added: z.number().int() });
const limits = { inputBytes: 262_144, outputBytes: 1024, timeoutMs: 15_000 };

/** One batch route: check the caller is a device, store the new rows, place ring notes, then wake the webhooks that
 *  take what changed. `after` counts the notes it placed. */
function batch<Item>(name: string, kind: Kind, items: z.ZodType<Item[]>, description: string,
  save: (db: Db, device: string, rows: Item[]) => Promise<number>, after?: (db: Db, rows: Item[]) => Promise<number>): Action {
  return defineAction({
    operationId: `relay.${name}-add`, summary: `Store a phone's ${name}`, description,
    input: z.strictObject({ [name]: items.describe(`Up to ${BATCH} rows; a row stored before is skipped.`) }),
    output, encoding: "json", effect: "write", agentAvailable: false, errors: {}, examples: [], limits,
    async handler(_request, env, { identity, input }) {
      const device = await deviceOf(env, identity);
      if (!device) return refused(403, "Only a Relay device key can send this");
      const rows = (input as Record<string, Item[]>)[name];
      const db = session(env);
      const added = await save(db, device.id, rows);
      const placed = await after?.(db, rows) ?? 0;
      await wake(env, [...(added ? [kind] : []), ...(placed ? ["notes" as const] : [])]);
      return Response.json({ received: rows.length, added });
    },
  });
}

const field = (name: string) => `json_extract(value, '$.${name}')`;

export const health = batch("samples", "health", z.array(sample).min(1).max(BATCH),
  "Store steps, heart rate, sleep and workouts from Apple Health or Health Connect, once per type, time span and source.",
  (db, device, rows) => insertNew(db, `INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at)
    SELECT ?, ${["type", "start", "end", "value", "unit", "source"].map(field).join(", ")}, ? FROM json_each(?) WHERE true
    ON CONFLICT (device_id, type, start_at, end_at, source) DO NOTHING RETURNING id`, device, Date.now(), JSON.stringify(rows)));

export const locations = batch("points", "locations", z.array(point).min(1).max(BATCH),
  "Store the phone's location history, once per time, and give ring notes near those times their place.",
  (db, device, rows) => insertNew(db, `INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, place, created_at)
    SELECT ?, ${["at", "lat", "lon", "accuracy", "place"].map(field).join(", ")}, ? FROM json_each(?) WHERE true
    ON CONFLICT (device_id, at) DO NOTHING RETURNING id`, device, Date.now(), JSON.stringify(rows)),
  (db, rows) => placeRingNotes(db, Math.min(...rows.map(row => row.at)), Math.max(...rows.map(row => row.at))));
