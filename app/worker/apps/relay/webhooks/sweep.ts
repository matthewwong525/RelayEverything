// Two ways a webhook catches up: past data from a date the owner picks, and the sweep, which runs every webhook left
// behind by a lost wake-up and keeps 30 days of tries. Production runs the sweep every 15 minutes.
import { MINUTE, session, type Db, type Env } from "../store.ts";
import { BEHIND, wakeEach } from "./send.ts";

const KEEP = 30 * 24 * 60 * MINUTE;

/** Moves the webhook's place back to just before the first entry logged for `since` or later, and runs it. Items stored
 *  late can come a little before `since`; receivers upsert, so that is harmless. False when no webhook has `id`. */
export async function backfill(env: Env, db: Db, id: string, since: number): Promise<boolean> {
  const row = await db.prepare(`UPDATE relay_webhooks SET
      sent_seq = coalesce((SELECT min(seq) - 1 FROM relay_outbox WHERE at >= ?), (SELECT coalesce(max(seq), 0) FROM relay_outbox)),
      backfill_seq = (SELECT coalesce(max(seq), 0) FROM relay_outbox),
      pending_seq = NULL, lease_until = NULL, tries = 0, next_try_at = NULL, failing_since = NULL
    WHERE id = ? RETURNING id`).bind(since, id).first();
  if (row) await wakeEach(env, [id]);
  return !!row;
}

/** Runs every webhook whose place is behind the log, and drops tries older than 30 days. Says how many it ran. */
export async function sweep(env: Env): Promise<number> {
  const db = session(env);
  const { results } = await db.prepare(`SELECT w.id FROM relay_webhooks w WHERE ${BEHIND}`).bind(Date.now()).all<{ id: string }>();
  await wakeEach(env, results.map(({ id }) => id));
  await db.prepare("DELETE FROM relay_webhook_attempts WHERE at < ?").bind(Date.now() - KEEP).run();
  return results.length;
}
