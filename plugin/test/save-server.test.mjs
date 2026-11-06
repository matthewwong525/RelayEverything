import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { PassThrough } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { record, run } from '../bin/hook.mjs';
import { answer, serve, TOOL } from '../bin/save-server.mjs';
import { connectCode, fakeServer, project, said, SESSION } from './fake.mjs';

const SERVER = fileURLToPath(new URL('../bin/save-server.mjs', import.meta.url));
const call = (place, server, args, env = {}) => answer({ jsonrpc: '2.0', id: 7, method: 'tools/call', params: { name: 'save_to_relay', arguments: args } },
  { env: { RELAY_CONNECT_CODE: connectCode(), CLAUDE_CODE_SESSION_ID: SESSION, ...env }, store: place.store, cwd: place.root, fetcher: server.fetch });
const text = reply => reply.result.content[0].text;

/** Sends lines to a stream server and reads one answer per request. */
async function talk(input, output, requests) {
  const lines = createInterface({ input: output })[Symbol.asyncIterator]();
  const answers = [];
  for (const request of requests) {
    input.write(`${typeof request === 'string' ? request : JSON.stringify(request)}\n`);
    if (request.id !== undefined || typeof request === 'string') answers.push(JSON.parse((await lines.next()).value));
  }
  return answers;
}

test('answers initialize and lists save_to_relay over stdio, as Claude Code starts it', async () => {
  const place = project();
  const child = spawn(process.execPath, [SERVER], { env: { ...process.env, CLAUDE_PLUGIN_DATA: place.data }, stdio: ['pipe', 'pipe', 'inherit'] });
  const [init, list, unknown] = await talk(child.stdin, child.stdout, [
    { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'test' } } },
    { jsonrpc: '2.0', method: 'notifications/initialized' },
    { jsonrpc: '2.0', id: 2, method: 'tools/list' },
    { jsonrpc: '2.0', id: 3, method: 'resources/list' },
  ]);
  child.stdin.end();
  await once(child, 'exit');
  assert.deepEqual(init.result, { protocolVersion: '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'relay-save', version: '0.1.0' } });
  assert.deepEqual(list.result.tools.map(tool => [tool.name, tool.annotations.readOnlyHint]), [['save_to_relay', false]]);
  assert.equal(unknown.error.code, -32601);
});

test('a call sends the chat, then the save beside it', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  const reply = await call(place, server, { title: 'Stiffener plan', summary: 'Use 0.2 mm steel, glued.' });
  assert.equal(text(reply), 'Saved to Relay Everything: Stiffener plan');
  assert.deepEqual(server.calls.map(item => item.route), ['chats', 'chat-saves']);
  assert.deepEqual(server.saves, [{ sessionId: SESSION, title: 'Stiffener plan', text: 'Use 0.2 mm steel, glued.' }]);
  // A chat deleted on the server since goes again whole, then the save.
  server.chats.clear();
  assert.equal(text(await call(place, server, { title: 'Again', summary: 'Again.' })), 'Saved to Relay Everything: Again');
  assert.deepEqual(server.calls.map(item => item.route).slice(2), ['chat-saves', 'chats', 'chat-saves']);
  assert.equal(server.chats.get(SESSION).length, 2);
});

test('after /clear, a call saves the chat that follows, though the save tool keeps the cleared chat\'s id', async () => {
  const place = project();
  const server = fakeServer();
  // Chat A runs, and the save tool starts with its id.
  await run('stop', place.input, { env: place.env, fetcher: server.fetch });
  // /clear ends chat A and starts chat B in the same Claude Code run.
  await run('session-end', { ...place.input, reason: 'clear', hook_event_name: 'SessionEnd' }, { env: place.env, start: () => {} });
  assert.equal(place.store.sessions()[SESSION].cleared, true);
  const chatB = join(place.home, 'chat-b.jsonl');
  writeFileSync(chatB, `${said('you', 'A new question')}\n`);
  const b = { ...place.input, session_id: 'chat-b-session-01', transcript_path: chatB, hook_event_name: 'SessionStart' };
  await run('session-start', b, { env: place.env, fetcher: server.fetch });
  // An older chat in the same project is not the newest.
  record(place.store, { ...place.input, session_id: 'older-session-01' }, Date.now() - 60_000);
  const reply = await call(place, server, { title: 'T', summary: 'S' }, { CLAUDE_CODE_SESSION_ID: SESSION });
  assert.equal(text(reply), 'Saved to Relay Everything: T');
  assert.deepEqual(server.saves.map(save => save.sessionId), ['chat-b-session-01']);
  assert.deepEqual(server.chats.get('chat-b-session-01').map(message => message.text), ['A new question']);
  // An id this computer never recorded falls back the same way.
  await call(place, server, { title: 'T', summary: 'S' }, { CLAUDE_CODE_SESSION_ID: 'never-recorded-1' });
  assert.equal(server.saves[1].sessionId, 'chat-b-session-01');
  // A cleared chat you resume is that chat again.
  await run('session-start', { ...place.input, hook_event_name: 'SessionStart' }, { env: place.env, fetcher: server.fetch });
  await call(place, server, { title: 'T', summary: 'S' }, { CLAUDE_CODE_SESSION_ID: SESSION });
  assert.equal(server.saves[2].sessionId, SESSION);
  const elsewhere = { ...place, root: place.home };
  assert.match(text(await call(elsewhere, server, { title: 'T', summary: 'S' }, { CLAUDE_CODE_SESSION_ID: 'x' })), /has not seen this chat/);
});

test('refuses in a project with saving off, and says how to turn it on', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  place.store.setOff(place.root, true);
  const reply = await call(place, server, { title: 'T', summary: 'S' });
  assert.deepEqual([reply.result.isError, text(reply)], [true, 'Saving to Relay Everything is off in this project. To turn it on, type /relay:saving on.']);
  assert.match(text(await call(place, server, { title: 'T', summary: 'S' }, { RELAY_SAVE: '0' })), /RELAY_SAVE is 0/);
  assert.equal(server.calls.length, 0);
});

test('says what went wrong when it can\'t save', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  assert.match(text(await call(place, server, { title: ' ', summary: 'S' })), /Give a title and a summary/);
  assert.match(text(await call(place, server, { title: 'T', summary: 'S' }, { RELAY_CONNECT_CODE: '' })), /no connect code/);
  server.down = true;
  assert.match(text(await call(place, server, { title: 'T', summary: 'S' })), /could not take this chat now/);
  server.down = false;
  const refusing = { fetch: async (url, init) => url.endsWith('chat-saves') ? new Response('{}', { status: 500 }) : server.fetch(url, init) };
  assert.match(text(await call(place, refusing, { title: 'T', summary: 'S' })), /could not keep the save/);
});

test('serves line-delimited JSON-RPC, answers a broken line, and a failed call', async () => {
  const input = new PassThrough();
  const output = new PassThrough();
  const place = project();
  record(place.store, place.input);
  const env = { RELAY_CONNECT_CODE: connectCode(), CLAUDE_CODE_SESSION_ID: SESSION };
  serve({ env, store: place.store, cwd: place.root, fetcher: async () => { throw new Error('down'); } }, input, output);
  const [broken, ping, failed] = await talk(input, output, ['{', { jsonrpc: '2.0', id: 1, method: 'ping' },
    { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'save_to_relay', arguments: { title: 'T', summary: 'S' } } }]);
  assert.equal(broken.error.code, -32700);
  assert.deepEqual(ping.result, {});
  assert.equal(failed.result.isError, true);
  assert.equal(TOOL.inputSchema.required.length, 2);
});
