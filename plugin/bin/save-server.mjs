#!/usr/bin/env node
// A small MCP server over stdio with one tool, save_to_relay: it sends this chat, then the AI's title and summary
// beside it. Written by hand, with no packages, so the plugin installs with no build step.
import { realpathSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { codeFrom, post } from '../lib/code.mjs';
import { hider } from '../lib/hide.mjs';
import { sendSession } from '../lib/send.mjs';
import { dataDir, state } from '../lib/state.mjs';
import { projectRoot } from '../lib/transcript.mjs';

const TITLE_CHARACTERS = 200;
const SUMMARY_CHARACTERS = 20_000;
const SEND_WAIT = 15_000;
export const TOOL = {
  name: 'save_to_relay',
  title: 'Save to Relay Everything',
  description: 'Save this chat to Relay Everything, with a short title and a summary you write of what was decided and why. '
    + 'Use it when the person asks to save the chat, a plan or a decision to Relay Everything.',
  inputSchema: {
    type: 'object',
    properties: {
      title: { type: 'string', description: 'A few words that name what the chat decided.', maxLength: TITLE_CHARACTERS },
      summary: { type: 'string', description: 'What was decided and why, in plain words.', maxLength: SUMMARY_CHARACTERS },
    },
    required: ['title', 'summary'],
  },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true },
};
const OFF = 'Saving to Relay Everything is off in this project. To turn it on, type /relay:saving on.';
const said = (text, isError = false) => ({ content: [{ type: 'text', text }], ...(isError ? { isError } : {}) });

/**
 * This chat's session: its own id, else the newest session in the same project. The save tool starts once per Claude
 * Code run, so after /clear its id is the cleared chat's: a cleared session is never this chat.
 */
export function findSession(store, env, cwd) {
  const sessions = store.sessions();
  const own = sessions[env.CLAUDE_CODE_SESSION_ID];
  if (own && !own.cleared) return env.CLAUDE_CODE_SESSION_ID;
  const root = projectRoot(cwd);
  return Object.entries(sessions).filter(([, item]) => item.root === root && !item.cleared)
    .sort(([, a], [, b]) => (b.seen ?? 0) - (a.seen ?? 0))[0]?.[0] ?? null;
}

/** Sends the chat, then the save; a chat deleted on the server since its last send goes again whole. */
export async function save({ title, summary }, { env, store, cwd, fetcher = fetch }) {
  if (typeof title !== 'string' || !title.trim() || typeof summary !== 'string' || !summary.trim()) {
    return said('Give a title and a summary.', true);
  }
  const id = findSession(store, env, cwd);
  if (!id) return said('Relay Everything has not seen this chat yet. Send one more message, then ask again.', true);
  if (env.RELAY_SAVE === '0') return said('Saving to Relay Everything is off, because RELAY_SAVE is 0 where Claude Code started.', true);
  const options = { env, store, fetcher, wait: SEND_WAIT };
  const hide = hider(store.sessions()[id].cwd);
  const body = { sessionId: id, title: hide(title.trim()).slice(0, TITLE_CHARACTERS), text: hide(summary.trim()).slice(0, SUMMARY_CHARACTERS) };
  for (const again of [false, true]) {
    if (again) store.update(id, { stored: 0 });
    const sent = await sendSession(id, options);
    if (sent === 'off') return said(OFF, true);
    if (sent === 'no-code') return said('The Relay Everything plugin has no connect code. Type /plugin, open relay, and enter it.', true);
    if (sent !== 'sent') return said('Relay Everything could not take this chat now. It sends it again at the next start; ask to save again then.', true);
    const { status } = await post(codeFrom(env), 'chat-saves', body, fetcher);
    if (status === 200) return said(`Saved to Relay Everything: ${body.title}`);
    if (status !== 404) break;
  }
  return said('Relay Everything could not keep the save. Try again in a minute.', true);
}

/** Answers one JSON-RPC request; a notification answers nothing. */
export async function answer(request, context) {
  const reply = result => ({ jsonrpc: '2.0', id: request.id, result });
  if (request.id === undefined) return null;
  if (request.method === 'initialize') {
    return reply({ protocolVersion: request.params?.protocolVersion ?? '2025-06-18', capabilities: { tools: {} },
      serverInfo: { name: 'relay-save', version: '0.1.0' } });
  }
  if (request.method === 'ping') return reply({});
  if (request.method === 'tools/list') return reply({ tools: [TOOL] });
  if (request.method === 'tools/call' && request.params?.name === TOOL.name) return reply(await save(request.params.arguments ?? {}, context));
  return { jsonrpc: '2.0', id: request.id, error: { code: -32601, message: `No method ${request.method}.` } };
}

/** Serves line-delimited JSON-RPC on stdin and stdout until stdin closes. */
export function serve(context, input = process.stdin, output = process.stdout) {
  createInterface({ input }).on('line', async line => {
    let request;
    try {
      request = JSON.parse(line);
    } catch {
      output.write(`${JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'That line is not JSON.' } })}\n`);
      return;
    }
    const reply = await answer(request, context).catch(() => request.id === undefined ? null
      : { jsonrpc: '2.0', id: request.id, result: said('Relay Everything could not be reached. Try again in a minute.', true) });
    if (reply) output.write(`${JSON.stringify(reply)}\n`);
  });
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const env = process.env;
  serve({ env, store: state(dataDir(env)), cwd: env.CLAUDE_PROJECT_DIR || process.cwd() });
}
