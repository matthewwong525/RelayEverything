import assert from 'node:assert/strict';
import { once } from 'node:events';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { run } from '../bin/hook.mjs';
import { copyOf, openState, writeComputer } from '../lib/config.mjs';
import { MEMORY_RUNS, MEMORY_SCRIPT, memoryEnv, memoryState, OWN_MEMORY, plugged, PROFILE, runMemory, whyOff, WRAPPER } from '../lib/memory.mjs';
import { connect, lookup, topics } from '../memory-profile.mjs';
import { dailyBlocker } from '../memory/scripts/lib/daily.mjs';
import { API, computer, copy, page, project, relayHome, repoWithWorktree, SECRET, SERVER, SESSION } from './fake.mjs';

const WEB = {
  'topics/battery.md': page('Battery', 'Stays 40 mAh; charger cable open', '', '2026-11-08'),
  'topics/ring/README.md': page('Ring', 'Bike ring v2: band, board, sync', '', '2026-11-10'),
  'topics/ring/charging.md': page('Charging', 'The dock and its cable'),
};

/** A real git project, and a connected Relay Everything folder with memory `on` and a copy of the web. */
function memoryHome({ on = true, api = API } = {}) {
  const { main } = repoWithWorktree();
  const env = relayHome();
  writeComputer(env, { ...computer(SERVER, on), api });
  copy(WEB, copyOf(env));
  return { root: main, env };
}

const unconfigured = (env, root) => assert.throws(() => connect({ root }, { env }), error => error.kind === 'unconfigured'
  && error.message.startsWith("Relay Everything's memory is not on here: "));

test('the profile\'s store is the person\'s own space with this computer\'s key, and only while memory is on here', () => {
  const { root, env } = memoryHome();
  const store = connect({ root }, { env });
  assert.equal(store.url, `${API}/memory`);
  assert.deepEqual(store.headers(), { Authorization: `Bearer ${SECRET}` });
  assert.equal(memoryState(env, root), 'on');
  // The plugin's own profile, as its scripts get it, is not a project's own memory.
  assert.equal(whyOff({ ...env, WONG_MEMORY_PROFILE: PROFILE }, root), null);
  // Each case that leaves the copy quiet.
  unconfigured({ ...env, RELAY_SAVE: '0' }, root);
  unconfigured(relayHome({ connected: false }), root);
  unconfigured({ ...env, WONG_MEMORY_PROFILE: join(root, 'elsewhere.mjs') }, root);
  unconfigured(env, mkdtempSync(join(tmpdir(), 'relay-no-git-')));
  openState(env).setOff(root, true);
  unconfigured(env, root);
  assert.equal(memoryState(env, root), 'off');
  openState(env).setOff(root, false);
  for (const own of [['.claude', 'skills', 'memory'], ['.agents', 'memory', 'profile.mjs']]) {
    mkdirSync(join(root, ...own), { recursive: true });
    unconfigured(env, root);
    assert.equal(whyOff(env, root), OWN_MEMORY);
    assert.equal(memoryState(env, root), 'repo');
    rmSync(join(root, own[0]), { recursive: true });
  }
  writeComputer(env, computer(SERVER, false));
  unconfigured(env, root);
  assert.equal(memoryState(env, root), 'off');
});

test('the profile\'s topics are the pages of the copy, read from the project\'s folder, and the top-level ones lead, newest first', () => {
  const { root, env } = memoryHome();
  const found = topics({ root }, { env }).sort((a, b) => a.tag.localeCompare(b.tag));
  assert.deepEqual(found.map(topic => [topic.tag, topic.hub]), [['battery', 1], ['ring', 0], ['ring/charging', null]]);
  for (const topic of found) {
    assert.equal(topic.kind, 'company');
    assert.deepEqual([topic.paths, topic.docs], [[topic.page], [topic.page]]);
    assert.match(readFileSync(join(root, topic.page), 'utf8'), /^---\ntitle: /);
  }
  assert.equal(found[0].summary, 'Stays 40 mAh; charger cable open');
});

test('a lookup adds the topic\'s newest notes and the chats behind its facts, and a failure adds nothing', async () => {
  const env = relayHome();
  const calls = [];
  const routes = {
    '/notes': { notes: [{ id: 'n1', title: '', text: `The battery ${'stays small '.repeat(20)}`, recordedAt: '2026-11-04T14:20:00-05:00' }] },
    '/memory': { facts: [{ sources: ['relay:chat/c1#4', 'relay:note/n1'] }, { sources: ['relay:chat/c2', 'relay:chat/c3', 'relay:chat/c4'] }] },
    '/chats/c1': { title: 'Battery size', saves: [{ text: 'Chose 40 mAh.' }] },
    '/chats/c2': { title: 'Cable', saves: [] },
  };
  const fetcher = async url => {
    const { pathname, searchParams } = new URL(url);
    const path = pathname.replace(/^\/v1/, '');
    calls.push([path, searchParams.get('tag')]);
    return routes[path] ? Response.json(routes[path]) : Response.json({ error: 'not_found' }, { status: 404 });
  };
  const lines = await lookup.after({ root: '/' }, { tags: ['battery'] }, { env, fetcher });
  assert.equal(lines[0], 'Relay Everything notes on battery:');
  assert.match(lines[1], /^- The battery stays small .*… \(n1, 2026-11-04\)$/);
  assert.ok(lines[1].length < 120);
  assert.deepEqual(lines.slice(2), ['Relay Everything chats behind battery\'s facts:', '- Battery size (c1): Chose 40 mAh.', '- Cable (c2)']);
  // Three chats at most: c4 is never read.
  assert.deepEqual(calls.map(([path]) => path).sort(), ['/chats/c1', '/chats/c2', '/chats/c3', '/memory', '/notes']);
  const down = async () => { throw new TypeError('fetch failed'); };
  assert.deepEqual(await lookup.after({ root: '/' }, { tags: ['battery'] }, { env, fetcher: down }), []);
  assert.deepEqual(await lookup.after({ root: '/' }, { tags: ['battery'] }, { env: relayHome({ connected: false }), fetcher }), []);
});

/** A memory stand-in that notes each event it runs, and adds `memory <event>`. */
function fakeMemory() {
  const ran = [];
  const memory = async event => { ran.push(event); return `memory ${event}`; };
  return { ran, memory };
}

test('with memory on, the hooks run memory\'s start, topics, edits and end, and the chat still saves', async () => {
  const place = project();
  writeComputer(place.env, computer(SERVER, true));
  copy(WEB, copyOf(place.env));
  const { ran, memory } = fakeMemory();
  const starts = [];
  const hook = (event, input = place.input) => run(event, { ...input, hook_event_name: event }, { env: place.env, start: args => starts.push(args), memory });
  assert.equal(await hook('session-start'), 'memory session-start');
  assert.equal(await hook('prompt', { ...place.input, prompt: 'the battery' }), 'memory prompt');
  assert.equal(await hook('before-edit'), 'memory before-edit');
  assert.equal(await hook('stop'), '');
  assert.equal(await hook('session-end'), '');
  assert.deepEqual(ran, ['session-start', 'prompt', 'before-edit', 'session-end']);
  assert.deepEqual(starts.map(args => args[0]), ['build', 'send', 'send']);
  // Memory's own background chat saves no chat and starts nothing, but memory still sees its start and end.
  ran.length = 0;
  starts.length = 0;
  const background = { ...place.env, WONG_MEMORY_RUN: '1' };
  assert.equal(await run('session-start', place.input, { env: background, start: args => starts.push(args), memory }), 'memory session-start');
  assert.equal(await run('session-end', place.input, { env: background, start: args => starts.push(args), memory }), '');
  assert.deepEqual([ran, starts], [['session-start', 'session-end'], []]);
});

test('a project with its own memory gets no topics from the plugin, and with memory off the plugin\'s topics show as before', async () => {
  const place = project();
  copy(WEB, copyOf(place.env));
  const { ran, memory } = fakeMemory();
  const starts = [];
  const hook = (event, input = place.input) => run(event, input, { env: place.env, start: args => starts.push(args), memory });
  // Off: the plugin's own topics, and an edit adds nothing.
  assert.match(JSON.parse(await hook('session-start')).hookSpecificOutput.additionalContext, /^Relay Everything topics/);
  assert.match(JSON.parse(await hook('prompt', { ...place.input, prompt: 'the battery' })).hookSpecificOutput.additionalContext, /topic battery/);
  assert.equal(await hook('before-edit'), '');
  assert.equal(await hook('session-end'), '');
  // Its own memory: the project's memory adds the topics, so the plugin adds none, and still saves the chat.
  writeComputer(place.env, computer(SERVER, true));
  mkdirSync(join(place.root, '.claude', 'skills', 'memory'), { recursive: true });
  assert.equal(await hook('session-start'), '');
  assert.equal(await hook('prompt', { ...place.input, prompt: 'the battery' }), '');
  assert.equal(await hook('before-edit'), '');
  assert.equal(await hook('session-end'), '');
  assert.deepEqual(ran, []);
  assert.deepEqual(starts.map(args => args[0]), ['build', 'send', 'sync', 'send']);
});

test('memory\'s scripts get the plugin\'s profile, with their background runs on', () => {
  const env = memoryEnv({ PATH: '/bin', WONG_MEMORY_NO_HEADLESS: '1' });
  assert.deepEqual(env, { PATH: '/bin', WONG_MEMORY_PROFILE: PROFILE });
  assert.equal(dailyBlocker({ env, state: {}, digest: { daily: {} }, day: '2026-11-12' }), null);
  assert.equal(dailyBlocker({ env, state: { off: true }, digest: { daily: {} }, day: '2026-11-12' }), 'off on this computer');
  assert.equal(plugged(`Pull a topic: \`node ${MEMORY_SCRIPT} pull <topic>\``),
    `Pull a topic: \`node "${WRAPPER}" pull <topic>\``);
});

test('each memory run fits in its hook\'s time limit', () => {
  const { hooks } = JSON.parse(readFileSync(new URL('../hooks/hooks.json', import.meta.url), 'utf8'));
  const limit = { 'session-start': 'SessionStart', prompt: 'UserPromptSubmit', 'before-edit': 'PreToolUse', 'session-end': 'SessionEnd' };
  for (const [event, { wait }] of Object.entries(MEMORY_RUNS)) {
    // The hook needs time of its own before and after memory's run.
    assert.ok(wait + 2_000 <= hooks[limit[event]][0].hooks[0].timeout * 1000, event);
  }
});

/** The variables of a real memory run: this computer's own homes and memory's state stay out of it. */
function realEnv(env) {
  const home = mkdtempSync(join(tmpdir(), 'relay-memory-home-'));
  return { ...env, PATH: process.env.PATH, HOME: home, XDG_DATA_HOME: join(home, 'data'), WONG_MEMORY_STATE_DIR: join(home, 'state') };
}

test('a message gets a topic once from memory\'s real script, with the plugin\'s command to pull it', async () => {
  const { root, env } = memoryHome();
  const input = { session_id: SESSION, cwd: root, hook_event_name: 'UserPromptSubmit', prompt: 'is the battery fine?' };
  const vars = realEnv(env);
  const first = JSON.parse(await runMemory('prompt', input, vars));
  assert.equal(first.hookSpecificOutput.hookEventName, 'UserPromptSubmit');
  assert.deepEqual(first.hookSpecificOutput.additionalContext.split('\n'),
    ['Topic battery: Stays 40 mAh; charger cable open', `Pull a topic: \`node "${WRAPPER}" pull <topic>\``]);
  assert.equal(await runMemory('prompt', input, vars), '');
});

test('memory\'s real start ends in its time limit when the server does not answer', async () => {
  const server = createServer(() => {});
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const { root, env } = memoryHome({ api: `http://127.0.0.1:${server.address().port}/v1` });
    const began = Date.now();
    const said = await runMemory('session-start', { session_id: SESSION, cwd: root, hook_event_name: 'SessionStart' }, realEnv(env));
    assert.ok(Date.now() - began < MEMORY_RUNS['session-start'].wait + 1_000);
    if (said) assert.equal(JSON.parse(said).hookSpecificOutput.hookEventName, 'SessionStart');
  } finally {
    server.closeAllConnections();
    server.close();
  }
});

test('the copy\'s chat start with sessions waiting starts their capture on its own, no daily tidy, and trims look-up counts to 30 days', async () => {
  const asked = [];
  const server = createServer((request, response) => {
    asked.push(request.url);
    const digest = request.url === '/v1/memory/v2/digest';
    response.writeHead(digest ? 200 : 404, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(digest ? { result: { facts: [], live: 0, threads: [], daily: null } } : { error: 'not here' }));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const { root, env } = memoryHome({ api: `http://127.0.0.1:${server.address().port}/v1` });
    const vars = realEnv(env);
    // No real model runs: the capture's agent command is a stand-in.
    const bin = join(vars.HOME, 'bin');
    mkdirSync(bin);
    for (const name of ['claude', 'codex']) {
      writeFileSync(join(bin, name), '#!/bin/sh\nexit 0\n');
      chmodSync(join(bin, name), 0o755);
    }
    vars.PATH = `${bin}:${vars.PATH}`;
    const machine = '0a0a0a0a-0000-4000-8000-000000000001';
    mkdirSync(join(vars.XDG_DATA_HOME, 'wongstack'), { recursive: true });
    writeFileSync(join(vars.XDG_DATA_HOME, 'wongstack', 'machine-id'), `${machine}\n`, { mode: 0o600 });
    const state = join(vars.WONG_MEMORY_STATE_DIR, machine);
    mkdirSync(join(state, 'spool'), { recursive: true });
    writeFileSync(join(state, 'spool', '1.json'), '{}');
    // Look-up counts older than 30 days go at the start, because the plugin runs no daily tidy to trim them.
    const day = 86_400_000;
    const old = { at: new Date(Date.now() - 40 * day).toISOString(), command: 'recall', topics: [], facts: [], miss: true, words: 'old question' };
    const recent = { at: new Date(Date.now() - day).toISOString(), command: 'recall', topics: [], facts: [] };
    writeFileSync(join(state, 'usage.jsonl'), `${JSON.stringify(old)}\n${JSON.stringify(recent)}\n`);
    const said = await runMemory('session-start', { session_id: SESSION, cwd: root, hook_event_name: 'SessionStart' }, vars);
    assert.ok(asked.includes('/v1/memory/v2/digest'), 'the store answered, so only the setting stops the tidy');
    const context = JSON.parse(said).hookSpecificOutput.additionalContext;
    assert.doesNotMatch(context, /subagent|could not start/);
    assert.deepEqual(JSON.parse(readFileSync(join(state, 'daily.json'), 'utf8')), { off: true });
    assert.ok(existsSync(join(state, 'registry.jsonl')));
    assert.deepEqual(readFileSync(join(state, 'usage.jsonl'), 'utf8').split('\n').filter(Boolean).map(line => JSON.parse(line)), [recent]);
  } finally {
    server.closeAllConnections();
    server.close();
  }
});
