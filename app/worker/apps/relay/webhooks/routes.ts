// A person's webhook routes, for the Relay Everything page. Only a signed-in person reaches them, in their own space,
// never a device key, and no answer holds a secret but the one that makes or replaces it.
import { z } from "zod";
import { defineAction, type Action, type ActionCall } from "../../../api/contract.ts";
import { asPerson } from "../caller.ts";
import type { PersonSpace } from "../space.ts";
import { refused, time, type Db, type Env } from "../store.ts";
import { checkAddress, REFUSALS } from "./address.ts";
import { webhookTest } from "./format.ts";
import { newSecret } from "./sign.ts";
import { TAKES } from "./log.ts";
import { post, record, wakeEach, type Hook, type Kind } from "./send.ts";
import { backfill } from "./sweep.ts";

const RECENT = 20;

const kind = z.enum(["notes", "health", "locations", "calendar"]);
const id = z.string().min(1).max(64).describe("The webhook's id.");
const attempt = z.strictObject({ at: z.number(), type: z.string(), status: z.number().nullable(), ms: z.number(),
  error: z.string().nullable(), first: z.number().nullable(), last: z.number().nullable() });
const webhook = z.strictObject({
  id: z.string(), name: z.string(), url: z.string(), kinds: z.array(kind),
  state: z.enum(["working", "paused", "failing", "backfilling"]).describe("backfilling: sending past data."),
  waiting: z.number().int().describe("How many stored items wait to be sent."),
  lastStatus: z.number().nullable(), lastError: z.string().nullable(), lastSentAt: z.number().nullable(),
  nextTryAt: z.number().nullable(), failingSince: z.number().nullable(), createdAt: z.number(),
  attempts: z.array(attempt).describe(`The last ${RECENT} tries, newest first.`),
});
const one = z.strictObject({ webhook });
const name = z.string().trim().min(1).max(80).describe("A name for the webhook, such as the database's.");
const url = z.string().max(2000).describe("The https address Relay Everything sends to.");
const kinds = z.array(kind).max(4).describe("What it takes besides notes, which always go: any of health, locations and calendar.");

type View = z.infer<typeof webhook>;
type Row = Hook & { waiting: number };
type Attempt = { webhook_id: string; at: number; type: string; status: number | null; ms: number; error: string | null;
  first_seq: number | null; last_seq: number | null };

const stateOf = (row: Hook): View["state"] => !row.active ? "paused" : row.failing_since !== null ? "failing"
  : row.backfill_seq !== null && row.sent_seq < row.backfill_seq ? "backfilling" : "working";

/** Each webhook as its card shows it, or only `only`; never its secret. */
async function views(db: Db, only: string | null = null): Promise<View[]> {
  const { results } = await db.prepare(`SELECT w.*, (SELECT count(*) FROM relay_outbox o WHERE o.seq > w.sent_seq AND ${TAKES}) AS waiting
    FROM relay_webhooks w WHERE ? IS NULL OR w.id = ? ORDER BY w.created_at, w.id`).bind(only, only).all<Row>();
  const { results: tries } = await db.prepare(`SELECT * FROM (SELECT *, row_number() OVER (PARTITION BY webhook_id ORDER BY at DESC, id DESC)
    AS rank FROM relay_webhook_attempts WHERE ? IS NULL OR webhook_id = ?) WHERE rank <= ${RECENT} ORDER BY at DESC, id DESC`)
    .bind(only, only).all<Attempt>();
  return results.map(row => ({ id: row.id, name: row.name, url: row.url, kinds: JSON.parse(row.kinds), state: stateOf(row),
    waiting: row.waiting, lastStatus: row.last_status, lastError: row.last_error, lastSentAt: row.last_sent_at,
    nextTryAt: row.next_try_at, failingSince: row.failing_since, createdAt: row.created_at,
    attempts: tries.filter(item => item.webhook_id === row.id).map(item => ({ at: item.at, type: item.type, status: item.status,
      ms: item.ms, error: item.error, first: item.first_seq, last: item.last_seq })) }));
}

const failure = (code: string, status: 400 | 404) => Response.json({ error: { code } }, { status });
const notFound = () => failure("not_found", 404);
/** The webhook as one answer, or not found when `row` is null: no webhook had the id. */
const answer = async (db: Db, row: unknown, id: string) => row ? Response.json({ webhook: (await views(db, id))[0] }) : notFound();
/** Notes always go; the ticks add health, location and calendar. */
const kindsOf = (ticked: Kind[]) => JSON.stringify(["notes", ...(["health", "locations", "calendar"] as const).filter(item => ticked.includes(item))]);
const refusalOf = (address: string, { url: page }: Pick<ActionCall, "url">) => {
  const refusal = checkAddress(address, page.hostname);
  return refusal && failure(refusal, 400);
};

type Owner = Pick<Action, "operationId" | "summary" | "description" | "input" | "output"> & Partial<Pick<Action, "effect" | "encoding">> &
  { handler: (env: Env, db: Db, input: never, call: ActionCall, space: PersonSpace) => Promise<Response> };

/** A route only a signed-in person reaches, in their own space, even if the device keys' routes change. */
const owner = ({ handler, ...action }: Owner) => defineAction({ encoding: "json", effect: "write", agentAvailable: false,
  errors: { not_found: "No webhook has this id.", ...REFUSALS }, examples: [], ...action, requiresIdentity: false,
  handler: asPerson<ActionCall>(({ env, space, call }) => handler(env, space.db, call.input as never, call, space)) });

/** Runs the webhook now, and keeps the space's alarm set for one whose wake-up is lost. */
const wakeOne = async (env: Env, space: PersonSpace, id: string) => {
  await wakeEach(env, space.personId, [id]);
  await space.watch();
};

export const list = owner({
  operationId: "relay.webhooks", summary: "List the webhooks", encoding: "none", effect: "read",
  description: "List the webhooks Relay Everything sends to, each with its state, what waits, its last answer and its recent tries.",
  input: z.strictObject({}), output: z.strictObject({ webhooks: z.array(webhook) }),
  handler: async (_env, db) => Response.json({ webhooks: await views(db) }),
});

export const add = owner({
  operationId: "relay.webhooks-add", summary: "Add a webhook",
  description: "Add an address that gets each new note, and the health, location and calendar ticked for it. The answer holds its secret, once.",
  input: z.strictObject({ name, url, kinds }), output: one.extend({ secret: z.string().describe("Shown this once.") }),
  handler: async (_env, db, input: { name: string; url: string; kinds: Kind[] }, call, space) => {
    const refusal = refusalOf(input.url, call);
    if (refusal) return refusal;
    const [made, secret] = [crypto.randomUUID(), newSecret()];
    await db.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at)
      VALUES (?, ?, ?, ?, ?, (SELECT coalesce(max(seq), 0) FROM relay_outbox), ?)`)
      .bind(made, input.name, input.url, secret, kindsOf(input.kinds), Date.now()).run();
    await space.watch();
    return Response.json({ webhook: (await views(db, made))[0], secret });
  },
});

export const update = owner({
  operationId: "relay.webhooks-update", summary: "Change a webhook",
  description: "Rename a webhook, change its address or ticks, or pause and resume it. A new address or ticks clear a failure.",
  input: z.strictObject({ id, name: name.optional(), url: url.optional(), kinds: kinds.optional(),
    active: z.boolean().optional().describe("False pauses it; true sends again from where it stopped.") }),
  output: one,
  handler: async (env, db, input: { id: string; name?: string; url?: string; kinds?: Kind[]; active?: boolean }, call, space) => {
    const refusal = input.url === undefined ? null : refusalOf(input.url, call);
    if (refusal) return refusal;
    const changed = input.url !== undefined || input.kinds !== undefined ? 1 : 0;
    const row = await db.prepare(`UPDATE relay_webhooks SET name = coalesce(?, name), url = coalesce(?, url), kinds = coalesce(?, kinds),
        active = coalesce(?, active), lease_until = NULL, pending_seq = CASE WHEN ? THEN NULL ELSE pending_seq END,
        tries = CASE WHEN ? THEN 0 ELSE tries END, next_try_at = CASE WHEN ? THEN NULL ELSE next_try_at END,
        failing_since = CASE WHEN ? THEN NULL ELSE failing_since END
      WHERE id = ? RETURNING active`).bind(input.name ?? null, input.url ?? null, input.kinds ? kindsOf(input.kinds) : null,
      input.active === undefined ? null : Number(input.active), changed, changed, changed, changed, input.id).first<{ active: number }>();
    if (row?.active) await wakeOne(env, space, input.id);
    return answer(db, row, input.id);
  },
});

export const remove = owner({
  operationId: "relay.webhooks-remove", summary: "Remove a webhook",
  description: "Stop sending to a webhook and delete its secret and its tries. Your notes stay in Relay Everything.",
  input: z.strictObject({ id }), output: z.strictObject({ removed: z.literal(true) }),
  handler: async (_env, db, input: { id: string }) => {
    const row = await db.prepare("DELETE FROM relay_webhooks WHERE id = ? RETURNING id").bind(input.id).first();
    return row ? Response.json({ removed: true }) : notFound();
  },
});

export const secret = owner({
  operationId: "relay.webhooks-secret", summary: "Make a new secret",
  description: "Replace a webhook's secret. The old one stops working at once; the answer holds the new one, once.",
  input: z.strictObject({ id }), output: z.strictObject({ secret: z.string().describe("Shown this once.") }),
  handler: async (_env, db, input: { id: string }) => {
    const made = newSecret();
    const row = await db.prepare("UPDATE relay_webhooks SET secret = ? WHERE id = ? RETURNING id").bind(made, input.id).first();
    return row ? Response.json({ secret: made }) : notFound();
  },
});

export const test = owner({
  operationId: "relay.webhooks-test", summary: "Send a test", effect: "external",
  description: "Send a signed webhook.test message now, and answer with what the address said. It sends no data.",
  input: z.strictObject({ id }),
  output: z.strictObject({ status: z.number().nullable().describe("The address's HTTP status, or null with no answer."), ms: z.number(),
    error: z.string().nullable() }),
  handler: async (_env, db, input: { id: string }, call) => {
    const hook = await db.prepare("SELECT id, name, url, secret FROM relay_webhooks WHERE id = ?").bind(input.id).first<Hook>();
    if (!hook) return notFound();
    const refusal = refusalOf(hook.url, call);
    if (refusal) return refusal;
    const result = await post(hook.url, hook.secret, `msg_${hook.id}_test_${Date.now()}`,
      JSON.stringify(webhookTest({ id: hook.id, name: hook.name }, Date.now())));
    await record(db, hook.id, "webhook.test", result);
    return Response.json(result);
  },
});

export const resend = owner({
  operationId: "relay.webhooks-resend", summary: "Send past data",
  description: "Send again everything the webhook takes that was recorded since a time, in the order Relay Everything stored it, then carry on.",
  input: z.strictObject({ id, since: time.describe("From this Unix time in milliseconds.") }), output: one,
  handler: async (env, db, input: { id: string; since: number }, _call, space) => {
    const found = await backfill(env, space, input.id, input.since);
    if (found) await space.watch();
    return answer(db, found, input.id);
  },
});

export const retry = owner({
  operationId: "relay.webhooks-retry", summary: "Try again now",
  description: "Clear a webhook's failure and send everything waiting, in order, from where it stopped.",
  input: z.strictObject({ id }), output: one,
  handler: async (env, db, input: { id: string }, _call, space) => {
    const row = await db.prepare(`UPDATE relay_webhooks SET failing_since = NULL, tries = 0, next_try_at = NULL, lease_until = NULL
      WHERE id = ? RETURNING id`).bind(input.id).first();
    if (row) await wakeOne(env, space, input.id);
    return answer(db, row, input.id);
  },
});

export const sweepNow = owner({
  operationId: "relay.webhooks-sweep", summary: "Run the sweep (previews only)", encoding: "none",
  description: "Run what your space's alarm runs every 15 minutes: send each of your webhooks left behind, and drop tries older than 30 days.",
  input: z.strictObject({}), output: z.strictObject({ woken: z.number().int() }),
  handler: async (env, _db, _input, _call, space) => env.WONG_ENVIRONMENT === "production"
    ? refused(403, "On the live server, your space runs the sweep every 15 minutes.") : Response.json({ woken: await space.sweep() }),
});
