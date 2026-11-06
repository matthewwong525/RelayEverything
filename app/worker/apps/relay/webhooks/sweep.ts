// How a webhook catches up on past data from a date the owner picks. A webhook left behind by a lost wake-up is the
// space's alarm's job: spaces-worker.ts.
import type { PersonSpace } from "../space.ts";
import type { Env } from "../store.ts";
import { wakeEach } from "./send.ts";

/** Moves the webhook's place back to just before the first entry logged for `since` or later, and runs it. Items stored
 *  late can come a little before `since`; receivers upsert, so that is harmless. False when no webhook has `id`. */
export async function backfill(env: Env, space: PersonSpace, id: string, since: number): Promise<boolean> {
  const row = await space.db.prepare(`UPDATE relay_webhooks SET
      sent_seq = coalesce((SELECT min(seq) - 1 FROM relay_outbox WHERE at >= ?), (SELECT coalesce(max(seq), 0) FROM relay_outbox)),
      backfill_seq = (SELECT coalesce(max(seq), 0) FROM relay_outbox),
      pending_seq = NULL, lease_until = NULL, tries = 0, next_try_at = NULL, failing_since = NULL
    WHERE id = ? RETURNING id`).bind(since, id).first();
  if (row) await wakeEach(env, space.personId, [id]);
  return !!row;
}
