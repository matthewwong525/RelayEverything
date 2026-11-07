// The send log's two tests, shared by the sender and each space's alarm.
import { KINDS } from "../kinds.ts";

const arms = KINDS.flatMap(kind => kind.log.map(log => `WHEN '${log}' THEN '${kind.id}'`)).join(" ");
/** True when the log entry `o` is of a kind the webhook `w` takes. */
export const TAKES = `(CASE o.kind ${arms} END) IN (SELECT value FROM json_each(w.kinds))`;
/** True when webhook `w` should send now: active, not failing, not waiting for a retry, and behind the log. */
export const BEHIND = `w.active = 1 AND w.failing_since IS NULL AND (w.next_try_at IS NULL OR w.next_try_at <= ?)
  AND EXISTS (SELECT 1 FROM relay_outbox o WHERE o.seq > w.sent_seq AND ${TAKES})`;
