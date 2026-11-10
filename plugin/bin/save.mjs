#!/usr/bin/env node
// `/relay:save`: sends this chat so far, then the AI's title and summary beside it.
// usage: node save.mjs [--session <id>] < title on the first line, then the summary
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { openState, readComputer } from '../lib/config.mjs';
import { hider } from '../lib/hide.mjs';
import { withSandbox } from '../lib/sandbox.mjs';
import { post } from '../lib/server.mjs';
import { sendSession } from '../lib/send.mjs';
import { projectRoot } from '../lib/transcript.mjs';

const TITLE_CHARACTERS = 200;
const SUMMARY_CHARACTERS = 20_000;
const SEND_WAIT = 15_000;
export const OFF = 'Saving to Relay Everything is off in this project. To turn it on, type /relay:saving on.';
export const NOT_CONNECTED = 'This computer is not connected to Relay Everything. Type /relay:connect to connect it.';

/** The title (the first line) and the summary (the rest) from the text on stdin. */
export function parseSave(text) {
  const [first = '', ...rest] = String(text ?? '').replace(/\r\n/g, '\n').trim().split('\n');
  return { title: first.replace(/^#+\s*/, '').trim(), summary: rest.join('\n').trim() };
}

/**
 * This chat's session. Claude Code gives the skill its session id, and Codex gives each command `CODEX_THREAD_ID`.
 * The first of those this computer recorded, and not cleared, wins; else the newest session in the same project. A
 * cleared session is never this chat: after /clear, Claude Code may still give the old id.
 */
export function findSession(store, { session, env, cwd }) {
  const sessions = store.sessions();
  for (const id of [session, env.CODEX_THREAD_ID, env.CLAUDE_CODE_SESSION_ID]) {
    if (id && sessions[id] && !sessions[id].cleared) return id;
  }
  const root = projectRoot(cwd);
  return Object.entries(sessions).filter(([, item]) => item.root === root && !item.cleared)
    .sort(([, a], [, b]) => (b.seen ?? 0) - (a.seen ?? 0))[0]?.[0] ?? null;
}

/** Sends the chat, then the save; a chat deleted on the server since its last send goes again whole. Answers `{ ok, line }`. */
export async function save({ title, summary }, { env, store, cwd, session, fetcher = fetch }) {
  const said = (line, ok = false) => ({ ok, line });
  if (!title || !summary) return said('Give a title on the first line, then the summary.');
  const id = findSession(store, { session, env, cwd });
  if (!id) return said('Relay Everything has not seen this chat yet. Send one more message, then ask again.');
  if (env.RELAY_SAVE === '0') return said('Saving to Relay Everything is off, because RELAY_SAVE is 0 where this app started.');
  const computer = readComputer(env);
  if (!computer) return said(NOT_CONNECTED);
  const options = { env, store, fetcher, wait: SEND_WAIT };
  const hide = hider(store.sessions()[id].cwd);
  const body = { sessionId: id, title: hide(title).slice(0, TITLE_CHARACTERS), text: hide(summary).slice(0, SUMMARY_CHARACTERS) };
  for (const again of [false, true]) {
    if (again) store.update(id, { stored: 0 });
    const sent = await sendSession(id, options);
    if (sent === 'off') return said(OFF);
    if (sent === 'no-key') return said(NOT_CONNECTED);
    if (sent !== 'sent') return said('Relay Everything could not take this chat now. It sends it again at the next start; ask to save again then.');
    let status;
    try {
      ({ status } = await post(computer, 'chat-saves', body, fetcher));
    } catch {
      break;
    }
    if (status === 200) return said(`Saved to Relay Everything: ${body.title}`, true);
    if (status !== 404) break;
  }
  return said('Relay Everything could not keep the save. Try again in a minute.');
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const args = process.argv.slice(2);
  const at = args.indexOf('--session');
  let text = '';
  for await (const part of process.stdin) text += part;
  const env = process.env;
  const cwd = env.CLAUDE_PROJECT_DIR || process.cwd();
  try {
    const { ok, line } = await save(parseSave(text), { env, store: openState(env), cwd, session: at >= 0 ? args[at + 1] : '' });
    console.log(line);
    process.exitCode = ok ? 0 : 1;
  } catch (error) {
    console.log(withSandbox('Relay Everything could not save this chat now. Try again in a minute.', error));
    process.exitCode = 1;
  }
}
