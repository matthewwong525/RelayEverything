import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { readdirSync, readFileSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { END_WAIT, record, run } from '../bin/hook.mjs';
import { BATCH_BYTES, BATCH_MESSAGES, ROUNDS, batch, sendPending, sendSession } from '../lib/send.mjs';
import { forgetComputer } from '../lib/config.mjs';
import { state } from '../lib/state.mjs';
import { fakeServer, inline, project, said, SECRET, SESSION } from './fake.mjs';

const stop = (place, server, env = place.env) => run('stop', place.input, { env, start: inline(server.fetch) });
const begin = (place, server, input) => run('session-start', input, { env: place.env, start: inline(server.fetch) });
const texts = (server, id = SESSION) => (server.chats.get(id) ?? []).map(message => `${message.role}: ${message.text}`);

test('sends a chat after each answer, only its new messages, and nothing when none are new', async () => {
  const place = project();
  const server = fakeServer();
  await stop(place, server);
  assert.deepEqual(texts(server), ['you: Hello', 'ai: Hi']);
  assert.deepEqual(server.calls[0].body, {
    sessionId: SESSION, app: 'claude-code', project: 'relay-ring', startedAt: Date.parse('2026-11-04T14:00:00.000Z'), title: 'Hello',
    messages: server.chats.get(SESSION),
  });
  place.add(said('you', 'And the battery?', 60), said('ai', '15 mAh.', 61));
  await stop(place, server);
  assert.deepEqual(server.calls[1].body.messages.map(message => message.seq), [2, 3]);
  await stop(place, server);
  assert.equal(server.calls.length, 2);
  assert.equal(place.store.sessions()[SESSION].stored, 4);
});

test('keeps each send under 500 messages and 4 MB', async () => {
  const many = Array.from({ length: 1200 }, (_, at) => said(at % 2 ? 'ai' : 'you', `Message ${at}`, at));
  const server = fakeServer();
  await stop(project(many), server);
  assert.deepEqual(server.calls.map(call => call.body.messages.length), [BATCH_MESSAGES, BATCH_MESSAGES, 1200 - 2 * BATCH_MESSAGES]);
  const big = Array.from({ length: 30 }, (_, at) => said(at % 2 ? 'ai' : 'you', `"${'é'.repeat(150_000)}"`, at));
  const bigServer = fakeServer();
  await stop(project(big), bigServer);
  assert.equal(bigServer.chats.get(SESSION).length, 30);
  assert.ok(bigServer.calls.length > 1 && bigServer.calls.every(call => call.bytes < BATCH_BYTES + 1000));
  assert.deepEqual(batch([{ text: 'x'.repeat(10) }], 0, BATCH_BYTES), [{ text: 'x'.repeat(10) }]);
});

test('sends again from the count the server holds, as after the chat was deleted there', async () => {
  const place = project();
  const server = fakeServer();
  await stop(place, server);
  server.chats.delete(SESSION);
  place.add(said('you', 'Still there?', 60));
  await stop(place, server);
  assert.deepEqual(server.calls.map(call => [call.body.messages[0].seq, call.body.messages.length]), [[0, 2], [2, 1], [0, 3]]);
  assert.deepEqual(texts(server), ['you: Hello', 'ai: Hi', 'you: Still there?']);
});

test('a failed send waits as pending, and the next start sends it', async () => {
  const place = project();
  const server = fakeServer();
  server.down = true;
  await stop(place, server);
  assert.equal(place.store.sessions()[SESSION].pending, true);
  server.down = false;
  await begin(place, server, { ...place.input, session_id: 'next-session-0001', hook_event_name: 'SessionStart' });
  assert.deepEqual(texts(server), ['you: Hello', 'ai: Hi']);
  assert.equal(place.store.sessions()[SESSION].pending, false);
  // A refusal it can't recover from waits too.
  const refusing = { fetch: async () => new Response('{}', { status: 403 }) };
  place.add(said('you', 'More', 60));
  await stop(place, refusing);
  assert.equal(place.store.sessions()[SESSION].pending, true);
});

test('a send waits for another send of the same chat, so two never run at once', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  const release = place.store.lock(SESSION);
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch }), 'busy');
  assert.equal(server.calls.length, 0);
  // The other send may have read the chat before its last messages, so this one waits as pending.
  assert.equal(place.store.sessions()[SESSION].pending, true);
  setTimeout(release, 300);
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch, wait: 2000 }), 'sent');
  assert.equal(place.store.sessions()[SESSION].pending, false);
  // A lock left by a send that died goes stale.
  const stuck = place.store.lock(SESSION);
  assert.ok(stuck);
  const old = new Date(Date.now() - 10 * 60_000);
  utimesSync(join(place.data, 'locks', `${SESSION}.lock`), old, old);
  assert.ok(place.store.lock(SESSION));
});

test('a send that holds the lock reads the chat again for a send that found it busy, and keeps it pending', async () => {
  const place = project();
  record(place.store, place.input);
  const server = fakeServer();
  const options = { env: place.env, store: place.store };
  // The holder read the chat before these messages; the busy send comes while the holder still sends.
  let busy = 0;
  const holderFetch = async (url, init) => {
    if (busy++ === 0) {
      place.add(said('you', 'One more thing', 60));
      assert.equal(await sendSession(SESSION, { ...options, fetcher: server.fetch }), 'busy');
    }
    return server.fetch(url, init);
  };
  assert.equal(await sendSession(SESSION, { ...options, fetcher: holderFetch }), 'sent');
  assert.deepEqual(texts(server), ['you: Hello', 'ai: Hi', 'you: One more thing']);
  assert.deepEqual([place.store.sessions()[SESSION].pending, place.store.sessions()[SESSION].again], [false, false]);
  // A busy send in every round: after the last round the holder lets go and the session stays pending.
  const always = async (url, init) => {
    place.add(said('you', `More ${busy}`, 60 + busy));
    assert.equal(await sendSession(SESSION, { ...options, fetcher: server.fetch }), 'busy');
    busy++;
    return server.fetch(url, init);
  };
  place.add(said('ai', 'Noted.', 70));
  const before = server.calls.length;
  assert.equal(await sendSession(SESSION, { ...options, fetcher: always }), 'sent');
  assert.equal(server.calls.length - before, ROUNDS);
  // The last round's busy message waits as pending, and the next start sends it.
  assert.equal(server.chats.get(SESSION).length, 4 + ROUNDS - 1);
  assert.equal(place.store.sessions()[SESSION].pending, true);
  await begin(place, server, { ...place.input, session_id: 'next-session-0001' });
  assert.equal(server.chats.get(SESSION).length, 4 + ROUNDS);
  assert.equal(place.store.sessions()[SESSION].pending, false);
});

test('a data folder that can\'t be written fails at once, and a held file lock stops waiting', async () => {
  const place = project();
  record(place.store, place.input);
  // The data folder becomes a file, so every open under it fails with ENOTDIR, not EEXIST.
  rmSync(place.data, { recursive: true });
  writeFileSync(place.data, '');
  const started = Date.now();
  assert.throws(() => place.store.update(SESSION, { pending: true }), { code: 'ENOTDIR' });
  assert.throws(() => place.store.lock(SESSION), { code: 'ENOTDIR' });
  await assert.rejects(run('stop', place.input, { env: place.env, start: inline(fakeServer().fetch) }));
  const hook = spawn(process.execPath, [new URL('../bin/hook.mjs', import.meta.url).pathname, 'stop'],
    { env: { ...process.env, ...place.env }, stdio: ['pipe', 'ignore', 'ignore'] });
  hook.stdin.end(JSON.stringify(place.input));
  assert.equal((await once(hook, 'exit'))[0], 0);
  assert.ok(Date.now() - started < 5000);
  // A lock another hook holds is waited for, but not forever.
  const held = project();
  const store = state(held.data, Date.now, { fileLockWait: 300 });
  writeFileSync(join(held.data, 'sessions.json.lock'), '');
  const waited = Date.now();
  assert.throws(() => store.update(SESSION, { pending: true }), /held sessions\.json for too long/);
  assert.ok(Date.now() - waited >= 300 && Date.now() - waited < 2000);
});

test('the send a session\'s end starts waits for a Stop send of the same chat, and waits as pending if it never ends', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  assert.equal(END_WAIT, 60_000);
  const release = place.store.lock(SESSION);
  setTimeout(release, 300);
  await run('send', SESSION, { env: place.env, fetcher: server.fetch, wait: END_WAIT });
  assert.deepEqual(texts(server), ['you: Hello', 'ai: Hi']);
  place.add(said('you', 'Last words', 60));
  const stuck = place.store.lock(SESSION);
  await run('send', SESSION, { env: place.env, fetcher: server.fetch, wait: 300 });
  assert.equal(place.store.sessions()[SESSION].pending, true);
  stuck();
  await begin(place, server, { ...place.input, session_id: 'next-session-0001' });
  assert.deepEqual(texts(server), ['you: Hello', 'ai: Hi', 'you: Last words']);
});

test('two chats\' hooks changing the sessions file at once both keep their change', async () => {
  const place = project();
  const STATE = new URL('../lib/state.mjs', import.meta.url).href;
  const writer = name => `import { state } from ${JSON.stringify(STATE)};
    const store = state(process.argv[1]);
    for (let at = 0; at < 40; at++) store.update(\`${name}-session-\${at}\`, { pending: true, seen: Date.now() });`;
  const children = ['first', 'second', 'third'].map(name =>
    spawn(process.execPath, ['--input-type=module', '-e', writer(name), place.data], { stdio: 'inherit' }));
  const codes = await Promise.all(children.map(child => once(child, 'exit').then(([code]) => code)));
  assert.deepEqual(codes, [0, 0, 0]);
  const kept = Object.entries(place.store.sessions()).filter(([, item]) => item.pending);
  assert.equal(kept.length, 120);
  assert.deepEqual(readdirSync(place.data).filter(name => name.endsWith('.lock') || name.endsWith('.tmp')), []);
});

test('sends nothing for a project with saving off, with RELAY_SAVE=0, or with nothing you typed', async () => {
  const server = fakeServer();
  const off = project();
  record(off.store, off.input);
  off.store.setOff(off.root, true);
  await stop(off, server);
  await stop(project(), server, { ...project().env, RELAY_SAVE: '0' });
  const quiet = project([said('ai', 'Hi')]);
  await stop(quiet, server);
  assert.equal(server.calls.length, 0);
  assert.equal(await sendSession(SESSION, { env: quiet.env, store: quiet.store, fetcher: server.fetch }), 'nothing');
  assert.equal(await sendSession('unknown-session', { env: quiet.env, store: quiet.store }), 'unknown');
  assert.equal(await sendSession('../../etc', { env: quiet.env, store: quiet.store }), 'unknown');
  const unconnected = project();
  record(unconnected.store, unconnected.input);
  forgetComputer(unconnected.env);
  assert.equal(await sendSession(SESSION, { env: unconnected.env, store: unconnected.store }), 'no-key');
  writeFileSync(quiet.transcript, '');
  quiet.store.update(SESSION, { transcript: join(quiet.home, 'gone.jsonl'), pending: true });
  assert.equal(await sendSession(SESSION, { env: quiet.env, store: quiet.store }), 'gone');
  assert.equal(quiet.store.sessions()[SESSION].pending, false);
});

test('hides keys and .env values before a message leaves, and logs no text, key or address', async () => {
  const place = project([said('you', 'The password is opensesame-42, keep it.'), said('ai', 'Noted.')]);
  writeFileSync(join(place.root, '.env'), 'DB_PASSWORD=opensesame-42\n');
  const server = fakeServer();
  await stop(place, server);
  server.down = true;
  place.add(said('you', 'Again', 60));
  await stop(place, server);
  assert.deepEqual(texts(server), ['you: The password is [hidden], keep it.', 'ai: Noted.']);
  const log = readFileSync(join(place.data, 'send.log'), 'utf8');
  assert.match(log, new RegExp(`${SESSION} sent, stored 2\\n.*${SESSION} pending, status none\\n$`));
  assert.doesNotMatch(log, /password|opensesame|Noted|Again|example\.com|made-up/);
  assert.doesNotMatch(readFileSync(join(place.data, 'sessions.json'), 'utf8'), new RegExp(SECRET));
});

test('keeps only the last 200 log lines, and forgets sessions after 30 days', () => {
  const place = project();
  for (let at = 0; at < 210; at++) place.store.log(`line ${at}`);
  const lines = readFileSync(join(place.data, 'send.log'), 'utf8').trim().split('\n');
  assert.deepEqual([lines.length, lines[0].endsWith('line 10')], [200, true]);
  let now = 0;
  const store = state(place.data, () => now);
  store.update('old-session-01', { seen: 0 });
  now = 31 * 24 * 60 * 60_000;
  store.update('new-session-01', { seen: now });
  assert.deepEqual(Object.keys(store.sessions()), ['new-session-01']);
});

test('a session\'s end starts a send that outlives Claude Code, and records the session first', async () => {
  const place = project();
  const started = [];
  await run('session-end', place.input, { env: place.env, start: (args, env) => started.push([args, env.RELAY_EVERYTHING_HOME]) });
  assert.deepEqual(started, [[['send', SESSION, String(END_WAIT)], place.env.RELAY_EVERYTHING_HOME]]);
  assert.equal(place.store.sessions()[SESSION].project, 'relay-ring');
  const server = fakeServer();
  await run('send', SESSION, { env: place.env, fetcher: server.fetch });
  assert.deepEqual(texts(server), ['you: Hello', 'ai: Hi']);
  // A hook with no session or with RELAY_SAVE=0 records nothing.
  await run('stop', { cwd: place.root }, { env: place.env, start: inline(server.fetch) });
  await run('stop', { ...place.input, session_id: 'other-session-1' }, { env: { ...place.env, RELAY_SAVE: '0' } });
  assert.deepEqual(Object.keys(place.store.sessions()), [SESSION]);
  await sendPending({ env: place.env, store: place.store, fetcher: server.fetch });
});
