#!/usr/bin/env node
// Claude Code's and Codex's hooks call this: `hook.mjs session-start|stop|session-end` with the hook's JSON on stdin.
// Each records the session, starts a send that runs on its own, and ends at once, so neither app waits: Codex does
// not run a hook marked async. The send is `hook.mjs send <session> <wait ms>`, or `hook.mjs pending` at a start.
// It prints nothing but one notice, once, when this computer is not connected, because a hook's output joins the chat.
import { spawn } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { openState, readComputer } from '../lib/config.mjs';
import { sendPending, sendSession } from '../lib/send.mjs';
import { SESSION } from '../lib/state.mjs';
import { projectName, projectRoot } from '../lib/transcript.mjs';

const self = fileURLToPath(import.meta.url);
// The send a session's end starts runs on its own, outside the hook's time limit, so it can wait for a Stop send.
export const END_WAIT = 60_000;
export const NOT_CONNECTED = 'Relay Everything: this computer is not connected, so chats are not saved. '
  + 'Type /relay:connect to connect it. This shows once.';

/** Notes where a session's transcript is, and its project. */
export function record(store, input, now = Date.now()) {
  const id = String(input.session_id ?? '');
  if (!SESSION.test(id) || typeof input.transcript_path !== 'string' || typeof input.cwd !== 'string') return null;
  const root = projectRoot(input.cwd);
  store.update(id, { transcript: input.transcript_path, cwd: input.cwd, root, project: projectName(root), seen: now });
  return id;
}

/**
 * Runs one hook event, and answers what to print. `start` runs a send on its own, as `hook.mjs <args>`. A session
 * ended by /clear is marked cleared, so the save skill, which may keep its old id, finds the chat that follows.
 */
export async function run(event, input, { env, fetcher = fetch, start = startSend, wait = END_WAIT }) {
  if (env.RELAY_SAVE === '0') return '';
  const store = openState(env);
  if (event === 'send') {
    await sendSession(input, { env, store, fetcher, wait });
    return '';
  }
  if (event === 'pending') {
    await sendPending({ env, store, fetcher });
    return '';
  }
  const id = record(store, input);
  if (event === 'session-start') {
    // A cleared chat that you resume is this chat again.
    if (id && store.sessions()[id]?.cleared) store.update(id, { cleared: false });
    if (Object.values(store.sessions()).some(session => session.pending)) await start(['pending'], env);
    if (readComputer(env) || store.marked('not-connected')) return '';
    store.mark('not-connected');
    return JSON.stringify({ systemMessage: NOT_CONNECTED });
  }
  if (event === 'stop' && id) await start(['send', id, '0'], env);
  else if (event === 'session-end' && id) {
    if (input.reason === 'clear') store.update(id, { cleared: true });
    await start(['send', id, String(END_WAIT)], env);
  }
  return '';
}

function startSend(args, env) {
  spawn(process.execPath, [self, ...args], { detached: true, stdio: 'ignore', env }).unref();
}

async function stdin() {
  let text = '';
  for await (const part of process.stdin) text += part;
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const [event, session, wait] = process.argv.slice(2);
  try {
    const own = event === 'send' || event === 'pending';
    const said = await run(event, own ? session : await stdin(), { env: process.env, wait: Number(wait ?? END_WAIT) || 0 });
    if (said) console.log(said);
  } catch {
    // A hook never stops the app: the next start sends what this one could not.
  }
}
