// POST stays: the phone's stays and trips, worked out on the phone from its points. Each is kept once per device, kind
// and start; a resend changes no row, so it wakes no webhook, and a stay that grew or got a name changes its row.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asDevice } from "./caller.ts";
import { BATCH, latitude, longitude, placeName, time, type Db } from "./store.ts";
import { wake } from "./webhooks/send.ts";

export const STAY_SOURCES = ["calendar", "map", "street", "point"] as const;
export const TRIP_MODES = ["walking", "running", "cycling", "driving", "flying", "unknown"] as const;

const span = { start: time, end: time, ongoing: z.boolean().optional().describe("True while the person is still there.") };
const stay = z.strictObject({
  kind: z.literal("stay"), ...span, lat: latitude, lon: longitude, name: placeName.describe("The best name the phone found."),
  address: placeName.optional().describe("The street, when the name came from the calendar or the map."),
  event: z.string().min(1).max(500).optional().describe("The calendar event that named the stay."),
  source: z.enum(STAY_SOURCES).describe("Where the name came from."),
});
const trip = z.strictObject({
  kind: z.literal("trip"), ...span, mode: z.enum(TRIP_MODES), km: z.number().min(0).max(40_000).describe("The distance, in km."),
});
const segment = z.discriminatedUnion("kind", [stay, trip]).refine(item => item.end >= item.start, "end comes before start.");
type Segment = z.infer<typeof segment>;

const FIELDS = ["end_at", "ongoing", "lat", "lon", "name", "address", "event", "source", "mode", "km"];
const field = (name: string) => `json_extract(value, '$.${name}')`;

/** Stores each stay or trip that is new or differs from its row; returns how many changed. */
async function save(db: Db, device: string, rows: Segment[]): Promise<number> {
  const { results } = await db.prepare(`INSERT INTO relay_stays (device_id, kind, start_at, ${FIELDS.join(", ")}, updated_at, created_at)
    SELECT ?1, ${field("kind")}, ${field("start")}, ${field("end")}, coalesce(${field("ongoing")}, 0),
      ${["lat", "lon", "name", "address", "event", "source", "mode", "km"].map(field).join(", ")}, ?2, ?2
    FROM json_each(?3) WHERE true
    ON CONFLICT (device_id, kind, start_at) DO UPDATE SET ${FIELDS.map(name => `${name} = excluded.${name}`).join(", ")},
      updated_at = excluded.updated_at
    WHERE ${FIELDS.map(name => `${name} IS NOT excluded.${name}`).join(" OR ")}
    RETURNING id`).bind(device, Date.now(), JSON.stringify(rows)).all();
  return results.length;
}

export const stays = defineAction({
  operationId: "relay.stays-add", summary: "Store a phone's stays and trips",
  description: "Store the stays and trips the phone worked out from its location points, once per device, kind and start. A stay sent again with a later end, or a better name, changes its row.",
  input: z.strictObject({ stays: z.array(segment).min(1).max(BATCH).describe(`Up to ${BATCH} stays and trips; one that has not changed is skipped.`) }),
  output: z.strictObject({ received: z.number().int(), changed: z.number().int() }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  limits: { inputBytes: 262_144, outputBytes: 1024, timeoutMs: 15_000 },
  handler: asDevice<ActionCall>("Only a Relay Everything device key can send this", async ({ space, device, env, call }) => {
    const rows = (call.input as { stays: Segment[] }).stays;
    const changed = await save(space.db, device.id, rows);
    await wake(env, space, changed ? ["locations"] : []);
    return Response.json({ received: rows.length, changed });
  }),
});
