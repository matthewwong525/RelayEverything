// Sends a chat's new messages to the computer's server, in batches under its caps, resuming from the count the
// server last stored. A failed send marks the session pending, and the next session start sends it again.
import { setTimeout as sleep } from 'node:timers/promises';
import { isCodexRollout, readCodexChat } from './codex.mjs';
import { readComputer } from './config.mjs';
import { hider } from './hide.mjs';
import { post } from './server.mjs';
import { SESSION } from './state.mjs';
import { readChat, savingOff, transcriptText } from './transcript.mjs';

export const BATCH_MESSAGES = 499;
export const BATCH_BYTES = 3_900_000;
const GAPS = 3;
// How many times one send reads the chat again for sends that found it busy, before it leaves the rest pending.
export const ROUNDS = 3;
const bytes = value => Buffer.byteLength(JSON.stringify(value));

/** The messages from `from` that fit one send beside an envelope of `envelope` bytes; always at least one. */
export function batch(messages, from, envelope) {
  const out = [];
  let size = envelope;
  for (const message of messages.slice(from, from + BATCH_MESSAGES)) {
    const more = bytes(message) + 1;
    if (out.length && size + more > BATCH_BYTES) break;
    out.push(message);
    size += more;
  }
  return out;
}

const failed = status => Object.assign(new Error('The send failed.'), { status });

/** Sends every message from the session's last stored count; answers the count the server holds after, and if it took any. */
async function upload(id, session, chat, computer, fetcher) {
  const envelope = { sessionId: id, app: chat.app, project: session.project, startedAt: chat.startedAt, title: chat.title || undefined };
  let stored = Math.min(session.stored ?? 0, chat.messages.length);
  let gaps = 0;
  let took = false;
  while (stored < chat.messages.length) {
    const messages = batch(chat.messages, stored, bytes({ ...envelope, messages: [] }));
    const { status, json } = await post(computer, 'chats', { ...envelope, messages }, fetcher);
    const told = Number.isInteger(json?.stored) ? json.stored : null;
    // The server holds fewer than this computer thinks, as after a delete: send again from its count.
    if (status === 400 && told !== null && told < stored && gaps++ < GAPS) stored = told;
    else if (status === 200 && told !== null && told > stored) [stored, took] = [told, true];
    else throw failed(status);
  }
  return { stored, took };
}

async function lockFor(store, id, wait) {
  for (const until = Date.now() + wait; ; await sleep(200)) {
    const release = store.lock(id);
    if (release || Date.now() >= until) return release;
  }
}

/**
 * Sends one session's chat and answers what happened: sent, off, nothing, unknown, no-key, busy, gone or pending.
 * `wait` is how long to wait for another send of the same chat to finish. After that, the session waits as pending and
 * marks `again`, because the other send may have read the chat before its last messages: the other send then reads it
 * once more before it lets go, and never clears a pending mark made while it ran.
 */
export async function sendSession(id, { env, store, fetcher = fetch, wait = 0, now = Date.now }) {
  const session = store.sessions()[id];
  if (!SESSION.test(id) || !session) return 'unknown';
  if (env.RELAY_SAVE === '0' || savingOff(store, session.root, session.top)) return 'off';
  const computer = readComputer(env);
  if (!computer) {
    store.log(`${id} not connected`);
    return 'no-key';
  }
  const release = await lockFor(store, id, wait);
  if (!release) {
    store.update(id, { pending: true, again: true });
    store.log(`${id} busy, pending`);
    return 'busy';
  }
  try {
    for (let round = 1; ; round++) {
      const current = store.update(id, { again: false });
      const { outcome, change } = await sendOnce(id, current, computer, fetcher, now);
      // A busy send in this round set `again`: send again, or after the last round keep the session pending.
      const after = store.update(id, latest => ({
        ...change, ...(latest.again ? { pending: true } : outcome === 'nothing' ? {} : { pending: false }),
      }));
      if (outcome === 'sent') store.log(`${id} sent, stored ${after.stored}`);
      if (!after.again) return outcome;
      if (round >= ROUNDS) {
        store.log(`${id} busy ${round} times, pending`);
        return outcome;
      }
    }
  } catch (error) {
    store.update(id, { pending: true });
    store.log(`${id} pending, status ${error.status ?? 'none'}`);
    return 'pending';
  } finally {
    release();
  }
}

/** A chat from a Claude Code transcript or a Codex rollout, with the app it came from. */
export function readAnyChat(text, options) {
  if (isCodexRollout(text)) return { ...readCodexChat(text, options), app: 'codex' };
  return { ...readChat(text, options), app: 'claude-code' };
}

/** Reads the chat once and sends what is new; answers the outcome and the fields to keep. */
async function sendOnce(id, session, computer, fetcher, now) {
  const text = transcriptText(session.transcript);
  if (text === null) return { outcome: 'gone', change: {} };
  const chat = readAnyChat(text, { cwd: session.cwd, hide: hider(session.cwd) });
  if (!chat.hasYou) return { outcome: 'nothing', change: {} };
  const { stored, took } = await upload(id, session, chat, computer, fetcher);
  return { outcome: 'sent', change: { stored, ...(took ? { sentAt: now() } : {}) } };
}

/** Sends each session a past send left pending. */
export async function sendPending(options) {
  for (const [id, session] of Object.entries(options.store.sessions())) {
    if (session.pending) await sendSession(id, options);
  }
}
