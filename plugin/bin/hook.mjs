#!/usr/bin/env node
// Claude Code's hooks call this: `hook.mjs session-start|stop|session-end` with the hook's JSON on stdin, and
// `hook.mjs send <session>` from a session's end. It prints nothing, because a start hook's output joins the chat.
import { spawn } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { sendPending, sendSession } from '../lib/send.mjs';
import { dataDir, SESSION, state } from '../lib/state.mjs';
import { projectName, projectRoot } from '../lib/transcript.mjs';

const self = fileURLToPath(import.meta.url);
// The send a session's end starts runs on its own, outside the hook's time limit, so it can wait for a Stop send.
export const END_WAIT = 60_000;

/** Notes where a session's transcript is, and its project. */
export function record(store, input, now = Date.now()) {
  const id = String(input.session_id ?? '');
  if (!SESSION.test(id) || typeof input.transcript_path !== 'string' || typeof input.cwd !== 'string') return null;
  const root = projectRoot(input.cwd);
  store.update(id, { transcript: input.transcript_path, cwd: input.cwd, root, project: projectName(root), seen: now });
  return id;
}

/**
 * Runs one hook event; `start` runs a detached send that outlives this process. A session ended by /clear is marked
 * cleared, so the save tool, which keeps its old id, finds the chat that follows.
 */
export async function run(event, input, { env, fetcher = fetch, start = startSend, endWait = END_WAIT }) {
  if (env.RELAY_SAVE === '0') return;
  const store = state(dataDir(env));
  if (event === 'send') {
    await sendSession(input, { env, store, fetcher, wait: endWait });
    return;
  }
  const id = record(store, input);
  if (event === 'session-start') {
    // A cleared chat that you resume is this chat again.
    if (id && store.sessions()[id]?.cleared) store.update(id, { cleared: false });
    await sendPending({ env, store, fetcher });
  }
  else if (event === 'stop' && id) await sendSession(id, { env, store, fetcher });
  else if (event === 'session-end' && id) {
    if (input.reason === 'clear') store.update(id, { cleared: true });
    start(id, env);
  }
}

function startSend(id, env) {
  spawn(process.execPath, [self, 'send', id], { detached: true, stdio: 'ignore', env }).unref();
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
  const [event, session] = process.argv.slice(2);
  try {
    await run(event, event === 'send' ? session : await stdin(), { env: process.env });
  } catch {
    // A hook never stops Claude Code: the next start sends what this one could not.
  }
}
