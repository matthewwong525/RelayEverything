// The sender: each webhook reads the send log from its own place, one group at a time, and moves its place only after a
// 2xx. A queue message only says "look now" for one webhook; the lease keeps one sender per webhook at a time.
import { spaceOf, vouch, type Files, type PersonSpace, type SpaceEnv } from "../space.ts";
import { MINUTE, type Db, type Env } from "../store.ts";
import { ownerOf, type Entry, type KindId, type WithFile } from "../kinds.ts";
import { checkAddress } from "./address.ts";
import { BEHIND, TAKES } from "./log.ts";
import { base64, signedHeaders } from "./sign.ts";
export type Hook = { id: string; name: string; url: string; secret: string; kinds: string; active: number; sent_seq: number;
  pending_seq: number | null; backfill_seq: number | null; lease_until: number | null; tries: number; next_try_at: number | null;
  failing_since: number | null; last_status: number | null; last_error: string | null; last_sent_at: number | null; created_at: number };
type Answer = { status: number | null; ms: number; error: string | null };
/** How a run ends: null acks its message, a number retries it in that many seconds. */
type Wait = number | null;

const BATCH = 500;
const PER_RUN = 20;
const LEASE = 2 * MINUTE;
const TIMEOUT = 15_000;
const SLACK = 5_000;
const AUDIO_RETRY = 30;
/** A multiple of 3, so each piece's base64 joins the next with no padding between. */
const PIECE = 3 * 0x2000;
/** Seconds before each retry after a failed send, about 22 hours in all; then the webhook shows as failing. */
export const DELAYS = [30, 120, 600, 1800, 3600, 7200, 14_400, 21_600, 28_800];

/** Asks the queue to run each of a person's webhooks now. The message names the person, whose space is opened. */
export async function wakeEach(env: Pick<Env, "RELAY_WEBHOOKS">, person: string, ids: string[]) {
  if (ids.length) await env.RELAY_WEBHOOKS.sendBatch(ids.map(webhook => ({ body: { webhook, person } })));
}

/** After a store: runs every active webhook that takes one of `kinds`. It never fails a route, as the sweep catches a
 *  lost wake-up. */
export async function wake(env: Pick<Env, "RELAY_WEBHOOKS">, space: PersonSpace, kinds: KindId[]) {
  if (!kinds.length) return;
  try {
    const { results } = await space.db.prepare(`SELECT id FROM relay_webhooks w WHERE active = 1 AND failing_since IS NULL
      AND EXISTS (SELECT 1 FROM json_each(w.kinds) WHERE value IN (SELECT value FROM json_each(?)))`)
      .bind(JSON.stringify(kinds)).all<{ id: string }>();
    await wakeEach(env, space.personId, results.map(({ id }) => id));
  } catch (error) {
    console.error("Relay Everything webhooks: the wake-up was lost", error);
  }
}

/** Takes the webhook's lease, or null when another sender holds it. The lease's time is its token. */
async function take(db: Db, id: string): Promise<number | null> {
  const until = Date.now() + LEASE;
  const row = await db.prepare(`UPDATE relay_webhooks SET lease_until = ? WHERE id = ? AND (lease_until IS NULL OR lease_until < ?)
    RETURNING id`).bind(until, id, Date.now()).first();
  return row ? until : null;
}

/** Renews the lease and reads the webhook, or null when the lease was lost: removed, changed by its owner, or taken. */
const renew = (db: Db, id: string, lease: number) => db.prepare(`UPDATE relay_webhooks SET lease_until = ?
  WHERE id = ? AND lease_until = ? RETURNING *`).bind(Date.now() + LEASE, id, lease).first<Hook>();

const release = (db: Db, id: string, lease: number) =>
  db.prepare("UPDATE relay_webhooks SET lease_until = NULL WHERE id = ? AND lease_until = ?").bind(id, lease).run();

const behind = async (db: Db, id: string) =>
  !!await db.prepare(`SELECT 1 FROM relay_webhooks w WHERE w.id = ? AND ${BEHIND}`).bind(id, Date.now()).first();

/** The next group: a note alone, or up to 500 health samples, location points or calendar events in a row. A frozen
 *  group ends at `pending_seq`, so every retry sends the same one. */
async function groupOf(db: Db, hook: Hook): Promise<Entry[]> {
  const { results } = await db.prepare(`SELECT o.seq, o.kind, o.ref, o.logged_at FROM relay_outbox o, relay_webhooks w
    WHERE w.id = ? AND o.seq > w.sent_seq AND (w.pending_seq IS NULL OR o.seq <= w.pending_seq) AND ${TAKES}
    ORDER BY o.seq LIMIT ${BATCH}`).bind(hook.id).all<Entry>();
  const [first] = results;
  if (!first || first.kind.startsWith("note.")) return results.slice(0, 1);
  const other = results.findIndex(entry => entry.kind !== first.kind);
  return other === -1 ? results : results.slice(0, other);
}

/** The message body for a group, built by the kind that owns its log rows. */
const bodyOf = (files: Files, db: Db, group: Entry[]) => ownerOf(group[0].kind)!.build!(files, db, group);

/** A message with its file's bytes as base64 in its empty `base64`, written into one array of exact size. A 25 MB file
 *  as one string, and its copies, could pass a Worker's 128 MB. */
export function bodyWithFile({ message, bytes }: WithFile): Uint8Array {
  const text = JSON.stringify(message);
  const at = text.lastIndexOf('"base64":""') + '"base64":"'.length;
  const encoder = new TextEncoder();
  const [prefix, suffix] = [encoder.encode(text.slice(0, at)), encoder.encode(text.slice(at))];
  const body = new Uint8Array(prefix.length + 4 * Math.ceil(bytes.length / 3) + suffix.length);
  body.set(prefix);
  let offset = prefix.length;
  for (let start = 0; start < bytes.length; start += PIECE) {
    offset += encoder.encodeInto(base64(bytes.subarray(start, start + PIECE)), body.subarray(offset)).written;
  }
  body.set(suffix, offset);
  return body;
}

/** One POST, with no redirects followed and 15 seconds to answer. */
export async function post(url: string, secret: string, id: string, body: string | Uint8Array): Promise<Answer> {
  const started = Date.now();
  try {
    const response = await fetch(url, { method: "POST", headers: await signedHeaders(secret, id, body), body, redirect: "manual",
      signal: AbortSignal.timeout(TIMEOUT) });
    await response.body?.cancel();
    const { status } = response;
    const error = status >= 300 && status < 400 ? "Answered with a redirect, which Relay Everything does not follow." : null;
    return { status, ms: Date.now() - started, error };
  } catch (error) {
    const timedOut = error instanceof Error && error.name === "TimeoutError";
    return { status: null, ms: Date.now() - started, error: timedOut ? "No answer in 15 seconds." : "Could not connect." };
  }
}

const succeeded = (answer: Answer) => answer.status !== null && answer.status >= 200 && answer.status < 300;

/** Keeps one try for the webhook's card; a removed webhook keeps none. */
export const record = (db: Db, id: string, type: string, answer: Answer, first: number | null = null, last: number | null = null) =>
  db.prepare(`INSERT INTO relay_webhook_attempts (webhook_id, at, first_seq, last_seq, type, status, ms, error)
    SELECT ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM relay_webhooks WHERE id = ?)`)
    .bind(id, Date.now(), first, last, type, answer.status, answer.ms, answer.error, id).run();

/** Moves the webhook's place to `seq`: the address took the group, skipped a file with `error`, or its note is gone. */
const advance = (db: Db, hook: Hook, lease: number, seq: number, answer?: Answer, error: string | null = null) => db.prepare(`UPDATE relay_webhooks
  SET sent_seq = ?, pending_seq = NULL, tries = 0, next_try_at = NULL, last_status = coalesce(?, last_status),
    last_error = CASE WHEN ? IS NULL THEN last_error ELSE ? END, last_sent_at = coalesce(?, last_sent_at)
  WHERE id = ? AND lease_until = ?`).bind(seq, answer?.status ?? null, answer?.status ?? null, error, answer ? Date.now() : null, hook.id, lease)
  .run();

const sizeOf = (bytes: number) => bytes < 1_000_000 ? `${Math.ceil(bytes / 1000)} KB` : `${(bytes / 1_000_000).toFixed(1)} MB`;
/** Why a file was skipped, for the card: the address refused it as too large, as the phone's own-webhook mode does. */
const tooLarge = ({ message: { data: { file } } }: WithFile) =>
  `Too large for this address: ${file.name} (${sizeOf(file.size)}). It stays on your Relay Everything page.`;

/** After a failed try: the wait before the next, or null once the webhook shows as failing. */
async function failed(db: Db, hook: Hook, lease: number, error: string, status: number | null = null): Promise<Wait> {
  const tries = hook.tries + 1;
  const delay = DELAYS[tries - 1] ?? null;
  await db.prepare(`UPDATE relay_webhooks SET tries = ?, next_try_at = ?, failing_since = ?, last_status = ?, last_error = ?
    WHERE id = ? AND lease_until = ?`).bind(tries, delay === null ? null : Date.now() + delay * 1000, delay === null ? Date.now() : null,
    status, error, hook.id, lease).run();
  return delay;
}

/** Sends the next group and says what follows: "next" for another, "done" when caught up, or how the run ends. */
async function step(files: Files, db: Db, hook: Hook, lease: number): Promise<"next" | "done" | { wait: Wait }> {
  const refusal = checkAddress(hook.url);
  if (refusal) return { wait: await failed(db, { ...hook, tries: DELAYS.length }, lease, `Relay Everything no longer sends to this address: ${refusal}.`) };
  const group = await groupOf(db, hook);
  if (!group.length) return "done";
  const last = group.at(-1)!.seq;
  const body = await bodyOf(files, db, group);
  if (body === "skip") {
    await advance(db, hook, lease, last);
    return "next";
  }
  if (body === "wait") return { wait: AUDIO_RETRY };
  await db.prepare("UPDATE relay_webhooks SET pending_seq = ? WHERE id = ? AND lease_until = ?").bind(last, hook.id, lease).run();
  const withFile = "bytes" in body ? body : null;
  const { type } = withFile?.message ?? body as { type: string };
  const answer = await post(hook.url, hook.secret, `msg_${hook.id}_${group[0].seq}_${last}`,
    withFile ? bodyWithFile(withFile) : JSON.stringify(body));
  // One file too large for the address must not hold back every note after it.
  const skipped = withFile && answer.status === 413 ? tooLarge(withFile) : null;
  await record(db, hook.id, type, skipped ? { ...answer, error: skipped } : answer, group[0].seq, last);
  if (skipped) {
    await advance(db, hook, lease, last, answer, skipped);
    return "next";
  }
  if (!succeeded(answer)) return { wait: await failed(db, hook, lease, answer.error ?? `Answered ${answer.status}.`, answer.status) };
  await advance(db, hook, lease, last, answer);
  return "next";
}

/** Sends groups while it holds the lease, up to `budget`, then gives the lease up. */
async function drain(files: Files, db: Db, id: string, lease: number, budget: number): Promise<{ sent: number; wait?: Wait }> {
  try {
    for (let sent = 0; sent < budget; sent++) {
      const hook = await renew(db, id, lease);
      if (!hook) return { sent, wait: null };
      // Each renewal writes a new time, and every later write, the release too, is guarded by it.
      lease = hook.lease_until!;
      // Paused, failing, or waiting for a retry that another message carries.
      if (!hook.active || hook.failing_since !== null || (hook.next_try_at ?? 0) > Date.now() + SLACK) return { sent, wait: null };
      const next = await step(files, db, hook, lease);
      if (next === "done") return { sent };
      if (next !== "next") return { sent, ...next };
    }
    return { sent: budget };
  } finally {
    await release(db, id, lease);
  }
}

/** One webhook's run. Before it ends, it looks at the log once more after giving up its lease, so a row stored during
 *  the run never waits for the sweep. After 20 messages it queues itself again, so one run stays short. */
export async function run(env: Env, space: PersonSpace, id: string): Promise<Wait> {
  const { db, files } = space;
  let sent = 0;
  // A new round only follows a row stored during the last one, so the loop ends once the stores stop.
  for (;;) {
    const lease = await take(db, id);
    if (lease === null) return null;
    const result = await drain(files, db, id, lease, PER_RUN - sent);
    sent += result.sent;
    if (result.wait !== undefined) return result.wait;
    if (!await behind(db, id)) return null;
    if (sent >= PER_RUN) {
      await wakeEach(env, space.personId, [id]);
      return null;
    }
  }
}

/** The queue's consumer, only on a Worker with SPACES: each message names a webhook and its person, whose space it
 *  opens. A message from before spaces names no person and is dropped. A run that fails on our side tries again. */
export async function consume(batch: MessageBatch, env: Env) {
  for (const message of batch.messages) {
    const { webhook, person } = (message.body ?? {}) as { webhook?: unknown; person?: unknown };
    try {
      const wait = typeof webhook === "string" && typeof person === "string" ? await run(env, spaceOf(env as SpaceEnv, vouch("queue", person)), webhook) : null;
      if (wait === null) message.ack();
      else message.retry({ delaySeconds: wait });
    } catch (error) {
      console.error("Relay Everything webhooks: a run failed", error);
      message.retry({ delaySeconds: AUDIO_RETRY });
    }
  }
}
