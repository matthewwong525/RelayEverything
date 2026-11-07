// POST calendar: a phone's new, changed and removed calendar events, each occurrence kept once per device by its
// key. A resend changes no row, so it wakes no webhook; a removed event is marked, never deleted, so its webhooks hear.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asDevice } from "./caller.ts";
import { time, type Db } from "./store.ts";
import { wake } from "./webhooks/send.ts";

/** Most events, and most removed keys, in one send. */
const EVENTS = 200;

const key = z.string().min(1).max(1000).describe("The phone's key for one occurrence: `<calendar>:<event>:<start ms>`.");
const person = z.strictObject({ name: z.string().min(1).max(200).optional(), email: z.string().min(1).max(320).optional(),
  organizer: z.boolean().optional() });
const event = z.strictObject({
  key, calendar: z.string().max(200).describe("The calendar's name; its id stays on the phone."), title: z.string().max(500),
  start: time, end: time, allDay: z.boolean(), location: z.string().max(500).optional(), notes: z.string().max(4000).optional(),
  url: z.string().max(2000).optional(), people: z.array(person).max(100),
}).refine(item => item.end >= item.start, "end comes before start.");

const FIELDS = ["calendar", "title", "start_at", "end_at", "all_day", "location", "notes", "url", "people"];
const field = (name: string) => `json_extract(value, '$.${name}')`;

/** Stores each event that is new or differs from its row, and brings back a removed one; returns how many changed. */
async function save(db: Db, device: string, events: z.infer<typeof event>[]): Promise<number> {
  if (!events.length) return 0;
  const { results } = await db.prepare(`INSERT INTO relay_calendar_events (device_id, event_key, ${FIELDS.join(", ")}, updated_at, created_at)
    SELECT ?1, ${["key", "calendar", "title", "start", "end", "allDay", "location", "notes", "url", "people"].map(field).join(", ")}, ?2, ?2
    FROM json_each(?3) WHERE true
    ON CONFLICT (device_id, event_key) DO UPDATE SET ${FIELDS.map(name => `${name} = excluded.${name}`).join(", ")},
      removed_at = NULL, updated_at = excluded.updated_at
    WHERE removed_at IS NOT NULL OR ${FIELDS.map(name => `${name} IS NOT excluded.${name}`).join(" OR ")}
    RETURNING id`).bind(device, Date.now(), JSON.stringify(events)).all();
  return results.length;
}

/** Marks the device's events with these keys removed; returns how many were still there. */
async function remove(db: Db, device: string, keys: string[]): Promise<number> {
  if (!keys.length) return 0;
  const { results } = await db.prepare(`UPDATE relay_calendar_events SET removed_at = ?1, updated_at = ?1
    WHERE device_id = ?2 AND removed_at IS NULL AND event_key IN (SELECT value FROM json_each(?3)) RETURNING id`)
    .bind(Date.now(), device, JSON.stringify(keys)).all();
  return results.length;
}

export const calendar = defineAction({
  operationId: "relay.calendar-add", summary: "Store a phone's calendar events",
  description: "Store the phone's new and changed calendar events, and mark the removed ones, once per device and occurrence.",
  input: z.strictObject({
    events: z.array(event).max(EVENTS).describe(`Up to ${EVENTS} new or changed events; one that has not changed is skipped.`),
    removed: z.array(key).max(EVENTS).describe(`Up to ${EVENTS} keys of events gone from the phone.`),
  }).refine(input => input.events.length + input.removed.length > 0, "Send at least one event or removed key."),
  output: z.strictObject({ received: z.number().int(), changed: z.number().int(), removed: z.number().int() }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  limits: { inputBytes: 262_144, outputBytes: 1024, timeoutMs: 15_000 },
  handler: asDevice<ActionCall>("Only a Relay Everything device key can send this", async ({ space, device, env, call }) => {
    const input = call.input as { events: z.infer<typeof event>[]; removed: string[] };
    const changed = await save(space.db, device.id, input.events);
    const removed = await remove(space.db, device.id, input.removed);
    await wake(env, space, changed + removed ? ["calendar"] : []);
    return Response.json({ received: input.events.length, changed, removed });
  }),
});
