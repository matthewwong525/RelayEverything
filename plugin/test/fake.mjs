// Test helpers: a fake Relay server that keeps chats as the real routes do, and a made-up project and transcript.
import { appendFileSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { state } from '../lib/state.mjs';

export const SESSION = '5d1c2b7a-0e4f-4a6b-9c3d-8e7f6a5b4c3d';
export const SECRET = `rek_${'made-up'.padEnd(43, 'x')}`;
export const connectCode = (server = 'https://relay.example.com') =>
  JSON.stringify({ relay: 1, server, key: SECRET });

const answer = (status, json) => new Response(JSON.stringify(json), { status, headers: { 'content-type': 'application/json' } });

/** A server that holds each session's messages in order, refuses gaps and caps, and can be taken down. */
export function fakeServer() {
  const server = { chats: new Map(), saves: [], calls: [], down: false };
  server.fetch = async (url, init) => {
    const body = JSON.parse(init.body);
    const route = url.split('/apps/relay/api/')[1];
    server.calls.push({ url, route, body, bytes: Buffer.byteLength(init.body) });
    if (server.down) throw new TypeError('fetch failed');
    if (route === 'chat-saves') {
      if (!server.chats.has(body.sessionId)) return answer(404, { error: { code: 'not_found' } });
      server.saves.push(body);
      return answer(200, { ok: true });
    }
    if (body.messages.length > 500 || Buffer.byteLength(init.body) > 4 * 1024 * 1024) return answer(413, { error: { code: 'too_large' } });
    const held = server.chats.get(body.sessionId) ?? [];
    if ((body.messages[0]?.seq ?? 0) > held.length) return answer(400, { error: { code: 'invalid_input' }, stored: held.length });
    for (const message of body.messages) if (message.seq === held.length) held.push(message);
    if (held.length) server.chats.set(body.sessionId, held);
    return answer(200, { stored: held.length });
  };
  return server;
}

/** A transcript line: `you` typed it, or the AI said it. */
export const said = (role, text, second = 0) => JSON.stringify({
  type: role === 'you' ? 'user' : 'assistant',
  timestamp: new Date(Date.parse('2026-11-04T14:00:00.000Z') + second * 1000).toISOString(),
  message: { role: role === 'you' ? 'user' : 'assistant', content: role === 'you' ? text : [{ type: 'text', text }] },
});

/** A git project, its transcript, the plugin's data folder, and the env a hook gets. */
export function project(lines = [said('you', 'Hello'), said('ai', 'Hi')]) {
  const home = mkdtempSync(join(tmpdir(), 'relay-plugin-'));
  const root = join(home, 'relay-ring');
  mkdirSync(join(root, '.git'), { recursive: true });
  const transcript = join(home, `${SESSION}.jsonl`);
  writeFileSync(transcript, `${lines.join('\n')}\n`);
  const data = join(home, 'data');
  const env = { CLAUDE_PLUGIN_DATA: data, CLAUDE_PLUGIN_OPTION_CONNECT_CODE: connectCode() };
  return {
    home, root, transcript, data, env, store: state(data),
    input: { session_id: SESSION, transcript_path: transcript, cwd: root, hook_event_name: 'Stop' },
    add: (...more) => appendFileSync(transcript, `${more.join('\n')}\n`),
  };
}
