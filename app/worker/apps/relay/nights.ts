// POST nights: the phone's nights, grouped on the phone from its sleep readings, one per source. Each is kept once per
// device, source and start; a resend changes no row, so it wakes no webhook, and a night that grew changes its row.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asDevice } from "./caller.ts";
import { BATCH, MAX_STAGES, SLEEP_STAGES, time, type Db, updateWhenChanged } from "./store.ts";
import { wake } from "./webhooks/send.ts";

const minutes = z.number().min(0).max(10_000);
const step = z.strictObject({ stage: z.enum(SLEEP_STAGES), start: time, end: time })
  .refine(item => item.end >= item.start, "end comes before start.");
const night = z.strictObject({
  source: z.string().min(1).max(200).describe("The app or watch that tracked the sleep."), start: time, end: time,
  asleepAt: time.optional().describe("When the person fell asleep."), wokeAt: time.optional().describe("When the person woke."),
  asleep: minutes.describe("Minutes asleep, in any stage."), core: minutes, deep: minutes, rem: minutes, awake: minutes,
  stages: z.array(step).max(MAX_STAGES).describe(`The stage timeline, in time order: at most ${MAX_STAGES} steps.`),
}).refine(item => item.end >= item.start, "end comes before start.");
type Night = z.infer<typeof night>;

const FIELDS = ["end_at", "asleep_at", "woke_at", "asleep", "core", "deep", "rem", "awake", "stages"];
const field = (name: string) => `json_extract(value, '$.${name}')`;

/** Stores each night that is new or differs from its row; returns how many changed. */
async function save(db: Db, device: string, rows: Night[]): Promise<number> {
  const { results } = await db.prepare(`INSERT INTO relay_nights (device_id, source, start_at, ${FIELDS.join(", ")}, updated_at, created_at)
    SELECT ?1, ${["source", "start", "end", "asleepAt", "wokeAt", "asleep", "core", "deep", "rem", "awake"].map(field).join(", ")},
      json(${field("stages")}), ?2, ?2
    FROM json_each(?3) WHERE true
    ON CONFLICT (device_id, source, start_at) ${updateWhenChanged(FIELDS)}
    RETURNING id`).bind(device, Date.now(), JSON.stringify(rows)).all();
  return results.length;
}

export const nights = defineAction({
  operationId: "relay.nights-add", summary: "Store a phone's nights",
  description: "Store the nights the phone grouped from its sleep readings, once per device, source and start, each with its stage minutes and timeline. A night sent again with a later end or other stages changes its row.",
  input: z.strictObject({ nights: z.array(night).min(1).max(BATCH).describe(`Up to ${BATCH} nights; one that has not changed is skipped.`) }),
  output: z.strictObject({ received: z.number().int(), changed: z.number().int() }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  limits: { inputBytes: 1_048_576, outputBytes: 1024, timeoutMs: 15_000 },
  handler: asDevice<ActionCall>("Only a Relay Everything device key can send this", async ({ space, device, env, call }) => {
    const rows = (call.input as { nights: Night[] }).nights;
    const changed = await save(space.db, device.id, rows);
    await wake(env, space, changed ? ["health"] : []);
    return Response.json({ received: rows.length, changed });
  }),
});
