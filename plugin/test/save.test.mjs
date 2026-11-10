import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { once } from 'node:events';
import { copyFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { NOT_CONNECTED as HOOK_NOT_CONNECTED, record, run } from '../bin/hook.mjs';
import { findSession, NOT_CONNECTED, OFF, parseSave, save } from '../bin/save.mjs';
import { forgetComputer, writeComputer } from '../lib/config.mjs';
import { computer, fakeServer, inline, project, said, SECRET, SESSION } from './fake.mjs';

const SAVE = fileURLToPath(new URL('../bin/save.mjs', import.meta.url));
const ROLLOUT = fileURLToPath(new URL('./fixtures/codex-rollout.jsonl', import.meta.url));
const CODEX_SESSION = '0b1d2c3e-4f50-7a6b-8c9d-0e1f2a3b4c5d';
const TEXT = { title: 'Stiffener plan', summary: 'We picked 0.2 mm steel.' };

test('parseSave takes the title from the first line and the summary from the rest', () => {
  assert.deepEqual(parseSave('# Stiffener plan\r\n\r\nWe picked\n0.2 mm steel.\n'), { title: 'Stiffener plan', summary: 'We picked\n0.2 mm steel.' });
  assert.deepEqual(parseSave(''), { title: '', summary: '' });
});

test('in Claude Code, save sends the chat by its session id, then the title and summary', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  record(place.store, { ...place.input, session_id: 'newer-session-01' }, Date.now() + 1000);
  const done = await save(TEXT, { env: place.env, store: place.store, cwd: place.root, session: SESSION, fetcher: server.fetch });
  assert.deepEqual(done, { ok: true, line: 'Saved to Relay Everything: Stiffener plan' });
  assert.deepEqual(server.calls.map(call => [call.route, call.body.sessionId]), [['chats', SESSION], ['chat-saves', SESSION]]);
  assert.deepEqual(server.saves, [{ sessionId: SESSION, title: 'Stiffener plan', text: 'We picked 0.2 mm steel.' }]);
  assert.equal(server.apps.get(SESSION), 'claude-code');
  assert.ok(server.calls.every(call => call.auth === `Bearer ${SECRET}`));
});

test('in Codex, save finds the chat by CODEX_THREAD_ID, else by the newest session in this folder', async () => {
  const place = project();
  const transcript = join(place.home, 'rollout.jsonl');
  copyFileSync(ROLLOUT, transcript);
  const codex = { session_id: CODEX_SESSION, transcript_path: transcript, cwd: place.root };
  const now = Date.now();
  record(place.store, place.input, now);
  record(place.store, codex, now - 500);
  // By the id Codex gives each command.
  assert.equal(findSession(place.store, { session: '', env: { CODEX_THREAD_ID: CODEX_SESSION }, cwd: place.root }), CODEX_SESSION);
  // An id this computer never saw does not count; the newest session in the folder does.
  assert.equal(findSession(place.store, { session: 'unknown-session', env: {}, cwd: place.root }), SESSION);
  record(place.store, codex, now + 1000);
  assert.equal(findSession(place.store, { session: '', env: {}, cwd: join(place.root, 'sub') }), CODEX_SESSION);
  assert.equal(findSession(place.store, { session: '', env: {}, cwd: place.home }), null);
  const server = fakeServer();
  const done = await save(TEXT, { env: { ...place.env, CODEX_THREAD_ID: CODEX_SESSION }, store: place.store, cwd: place.root, fetcher: server.fetch });
  assert.equal(done.ok, true);
  assert.equal(server.apps.get(CODEX_SESSION), 'codex');
  assert.equal(server.saves[0].sessionId, CODEX_SESSION);
});

test('after /clear the old id is not this chat: save takes the chat that follows', async () => {
  const place = project();
  const server = fakeServer();
  await run('session-start', place.input, { env: place.env, start: () => {} });
  await run('session-end', { ...place.input, reason: 'clear' }, { env: place.env, start: () => {} });
  await run('session-start', { ...place.input, session_id: 'after-clear-01' }, { env: place.env, start: () => {} });
  assert.equal(findSession(place.store, { session: SESSION, env: {}, cwd: place.root }), 'after-clear-01');
  // Resuming the cleared chat makes it this chat again.
  await run('session-start', place.input, { env: place.env, start: () => {} });
  assert.equal(findSession(place.store, { session: SESSION, env: {}, cwd: place.root }), SESSION);
  assert.equal(server.calls.length, 0);
});

test('save sends nothing when saving is off, when RELAY_SAVE is 0, or when the computer is not connected', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  const options = { env: place.env, store: place.store, cwd: place.root, session: SESSION, fetcher: server.fetch };
  place.store.setOff(place.root, true);
  assert.deepEqual(await save(TEXT, options), { ok: false, line: OFF });
  place.store.setOff(place.root, false);
  assert.match((await save(TEXT, { ...options, env: { ...place.env, RELAY_SAVE: '0' } })).line, /RELAY_SAVE is 0/);
  forgetComputer(place.env);
  assert.deepEqual(await save(TEXT, options), { ok: false, line: NOT_CONNECTED });
  assert.match((await save({ title: 'x', summary: '' }, options)).line, /^Give a title/);
  assert.equal(server.calls.length, 0);
});

test('a chat deleted on the server since its last send goes again whole, then the save lands', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  const options = { env: place.env, store: place.store, cwd: place.root, session: SESSION, fetcher: server.fetch };
  assert.equal((await save(TEXT, options)).ok, true);
  server.chats.clear();
  assert.equal((await save(TEXT, options)).ok, true);
  assert.equal(server.chats.get(SESSION).length, 2);
  server.down = true;
  assert.equal((await save(TEXT, options)).ok, false);
});

test('a Codex rollout goes as app codex through the hooks, with no reasoning or tool output', async () => {
  const place = project();
  const transcript = join(place.home, 'rollout.jsonl');
  copyFileSync(ROLLOUT, transcript);
  const server = fakeServer();
  const input = { session_id: CODEX_SESSION, transcript_path: transcript, cwd: place.root, hook_event_name: 'Stop', turn_id: 't1', stop_hook_active: false };
  assert.equal(await run('stop', input, { env: place.env, start: inline(server.fetch) }), '');
  const [call] = server.calls;
  assert.equal(call.body.app, 'codex');
  assert.equal(server.apps.get(CODEX_SESSION), 'codex');
  assert.ok(call.body.messages.some(message => message.role === 'you'));
  assert.ok(!JSON.stringify(call.body).includes('The board file says'));
});

test('the start hook says once, as a notice, that this computer is not connected, and sends a waiting chat on its own', async () => {
  const place = project(undefined, { connected: false });
  const starts = [];
  const start = args => starts.push(args);
  assert.equal(await run('session-start', place.input, { env: place.env, start }), JSON.stringify({ systemMessage: HOOK_NOT_CONNECTED }));
  assert.equal(await run('session-start', place.input, { env: place.env, start }), '');
  assert.deepEqual(starts, []);
  // A chat a send could not deliver waits; the next start sends it on its own.
  writeComputer(place.env, computer());
  const down = fakeServer();
  down.down = true;
  await run('stop', place.input, { env: place.env, start: inline(down.fetch) });
  assert.equal(place.store.sessions()[SESSION].pending, true);
  await run('session-start', place.input, { env: place.env, start });
  assert.deepEqual(starts, [['pending']]);
  assert.equal(await run('stop', place.input, { env: { ...place.env, RELAY_SAVE: '0' }, start }), '');
  assert.equal(starts.length, 1);
});

test('runs as the skill runs it: the text on stdin, the session id as an argument, against a local server', async () => {
  const place = project([said('you', 'Plan the stiffener'), said('ai', 'Use 0.2 mm steel')], { connected: false });
  const routes = [];
  const server = createServer((request, response) => {
    let body = '';
    request.on('data', part => { body += part; });
    request.on('end', () => {
      routes.push(request.url);
      const { messages = [] } = JSON.parse(body);
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify(request.url.endsWith('/chats') ? { stored: messages.length } : { ok: true }));
    });
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  writeComputer(place.env, computer(`http://127.0.0.1:${server.address().port}`));
  record(place.store, place.input);
  try {
    const child = execFile(process.execPath, [SAVE, '--session', SESSION], { cwd: place.root, env: { ...process.env, ...place.env, CLAUDE_PROJECT_DIR: '' } });
    child.stdin.end('Stiffener plan\nWe picked 0.2 mm steel.');
    let printed = '';
    child.stdout.on('data', part => { printed += part; });
    assert.equal((await once(child, 'exit'))[0], 0);
    assert.equal(printed, 'Saved to Relay Everything: Stiffener plan\n');
    assert.deepEqual(routes, ['/apps/relay/api/chats', '/apps/relay/api/chat-saves']);
  } finally {
    server.close();
  }
});

test('as the skill runs it, a folder it can not write prints one line, not a stack', async () => {
  const place = project([said('you', 'Hello')], { connected: false });
  // A file where the folder should be: openState fails, as it does in a read-only sandbox.
  const env = { RELAY_EVERYTHING_HOME: join(place.transcript, 'relay-everything') };
  const child = execFile(process.execPath, [SAVE], { cwd: place.root, env: { ...process.env, ...env, CLAUDE_PROJECT_DIR: '' } });
  child.stdin.end('A title\nA summary');
  let printed = '';
  child.stdout.on('data', part => { printed += part; });
  assert.equal((await once(child, 'exit'))[0], 1);
  assert.equal(printed, 'Relay Everything could not save this chat now. Try again in a minute.\n');
});
