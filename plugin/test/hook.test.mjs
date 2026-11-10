import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { once } from 'node:events';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { LINE_CHARACTERS, MOST_TOPICS, NOT_CONNECTED, run } from '../bin/hook.mjs';
import { copyOf } from '../lib/config.mjs';
import { copy, page, project } from './fake.mjs';

const HOOK = fileURLToPath(new URL('../bin/hook.mjs', import.meta.url));
const RELAY = fileURLToPath(new URL('../bin/relay.mjs', import.meta.url));

/** The text a hook adds to the AI's context, or null when it adds none. */
function added(printed, event) {
  if (!printed) return null;
  const { hookSpecificOutput } = JSON.parse(printed);
  assert.equal(hookSpecificOutput.hookEventName, event);
  return hookSpecificOutput.additionalContext;
}

/** A connected project whose computer holds a copy of the web with these pages. */
function withWeb(files, options) {
  const place = project(undefined, options);
  copy(files, copyOf(place.env));
  return place;
}

const WEB = {
  'topics/battery.md': page('Battery', 'Stays 40 mAh; charger cable open'),
  'topics/ring/README.md': page('Ring', 'Bike ring v2: band, board, sync'),
  'topics/ring/charging.md': page('Charging', 'The dock and its cable'),
  'topics/sam.md': page('Sam', 'Friend from the bike club'),
};

test('a chat starts with the top-level topics, how to pull one, and a sync of the copy on its own', async () => {
  const place = withWeb(WEB);
  const starts = [];
  const text = added(await run('session-start', place.input, { env: place.env, start: args => starts.push(args) }), 'SessionStart');
  assert.deepEqual(text.split('\n'), [
    'Relay Everything topics, from your knowledge web:',
    'battery  Stays 40 mAh; charger cable open',
    'ring     Bike ring v2: band, board, sync',
    'sam      Friend from the bike club',
    `Pull a topic with its links, facts, notes and chats: node "${RELAY}" topic <name>`]);
  assert.deepEqual(starts, [['sync']]);
  // Saving off for the project, or RELAY_SAVE=0, still lists them: they only read this computer's copy.
  place.store.setOff(place.root, true);
  assert.match(added(await run('session-start', place.input, { env: place.env, start: () => {} }), 'SessionStart'), /^battery {2}/m);
  const quiet = [];
  assert.match(added(await run('session-start', place.input, { env: { ...place.env, RELAY_SAVE: '0' }, start: args => quiet.push(args) }),
    'SessionStart'), /^ring {5}/m);
  assert.deepEqual(quiet, []);
});

test('the list holds at most 40 topics, the newest kept, each line cut to 80 characters', async () => {
  const files = {};
  for (let at = 0; at < MOST_TOPICS + 5; at++) {
    const name = `topic-${String(at).padStart(2, '0')}`;
    files[`topics/${name}.md`] = page(name, `A summary ${'that runs on '.repeat(at === 44 ? 10 : 0)}`, '', `2026-10-${String(at % 31 + 1).padStart(2, '0')}`);
  }
  const place = withWeb(files);
  const lines = added(await run('session-start', place.input, { env: place.env, start: () => {} }), 'SessionStart').split('\n');
  const topics = lines.slice(1, -1);
  assert.equal(topics.length, MOST_TOPICS);
  assert.ok(lines.every(line => line.length <= LINE_CHARACTERS || line.startsWith('Pull a topic')));
  // The 5 oldest `updated` are left out: topic-00 and topic-31 are both 2026-10-01, then 02, then one of the two 03s.
  for (const old of ['topic-00 ', 'topic-31 ', 'topic-01 ', 'topic-32 ', 'topic-33 ']) assert.ok(!topics.some(line => line.startsWith(old)), old);
  assert.ok(topics.some(line => line.startsWith('topic-02 ')));
  assert.ok(topics.some(line => line.startsWith('topic-44 ')));
});

test('the project\'s own topic joins the list; an empty copy, no copy, or no connection adds no topics', async () => {
  const place = withWeb({ ...WEB, 'topics/work/relay-ring/README.md': page('Relay ring', 'The ring project') });
  const text = added(await run('session-start', place.input, { env: place.env, start: () => {} }), 'SessionStart');
  assert.ok(text.split('\n').includes("This project's topic: work/relay-ring  The ring project"));
  // A project topic that is already in the list gets no second line.
  // The project is relay-ring; its path is built so the file names no address shape.
  const name = 'relay-ring';
  const listed = withWeb({ ...WEB, [`topics/${name}.md`]: page('Relay ring', 'The ring project') });
  const lines = added(await run('session-start', listed.input, { env: listed.env, start: () => {} }), 'SessionStart').split('\n');
  assert.ok(lines.some(line => line.startsWith(`${name} `)));
  assert.ok(!lines.some(line => line.startsWith("This project's topic")));
  const empty = withWeb({ 'README.md': '# Your knowledge web\n', 'FORMAT.md': '# The rules\n' });
  assert.equal(await run('session-start', empty.input, { env: empty.env, start: () => {} }), '');
  const none = project();
  assert.equal(await run('session-start', none.input, { env: none.env, start: () => {} }), '');
  const away = withWeb(WEB, { connected: false });
  const starts = [];
  assert.equal(await run('session-start', away.input, { env: away.env, start: args => starts.push(args) }), JSON.stringify({ systemMessage: NOT_CONNECTED }));
  assert.equal(await run('session-start', away.input, { env: away.env, start: args => starts.push(args) }), '');
  assert.equal(await run('prompt', { ...away.input, prompt: 'the battery' }, { env: away.env }), '');
  assert.deepEqual(starts, []);
});

test('a message gets the topics it names: a clear one with its summary, a weak one by name, none for no match', async () => {
  const place = withWeb({ ...WEB, 'topics/ring/band.md': page('Band') });
  const ask = async prompt => added(await run('prompt', { ...place.input, prompt }, { env: place.env }), 'UserPromptSubmit');
  assert.equal(await ask('is the battery still 40 mAh?'), 'Relay Everything topic battery: Stays 40 mAh; charger cable open');
  assert.equal(await ask('is it charging?'), 'Relay Everything topic ring/charging: The dock and its cable');
  assert.equal(await ask('the band'), 'Relay Everything topic ring/band: it has no summary yet.');
  assert.equal(await ask('how is the batt?'), 'Relay Everything topic battery may be what this message names.');
  assert.equal(await ask('what is for lunch?'), null);
  assert.equal((await ask('sam, the battery, the ring, the band')).split('\n').length, 3);
  // Saving off does not stop it: it only reads.
  assert.match(added(await run('prompt', { ...place.input, prompt: 'the battery' }, { env: { ...place.env, RELAY_SAVE: '0' } }),
    'UserPromptSubmit'), /battery/);
});

test('a message is matched fast against 1,000 topics, and the hook runs from stdin as the app runs it', async () => {
  const files = {};
  for (let at = 0; at < 1000; at++) files[`topics/area-${at % 20}/part${at}.md`] = page(`Part ${at}`, `Summary ${at}`);
  const place = withWeb(files);
  const began = performance.now();
  const text = added(await run('prompt', { ...place.input, prompt: 'what about part512?' }, { env: place.env }), 'UserPromptSubmit');
  assert.ok(performance.now() - began < 1000);
  assert.equal(text, 'Relay Everything topic area-12/part512: Summary 512');
  mkdirSync(join(place.root, 'app'));
  const child = execFile(process.execPath, [HOOK, 'prompt'], { env: { ...process.env, ...place.env } });
  let printed = '';
  child.stdout.on('data', part => { printed += part; });
  child.stdin.end(JSON.stringify({ ...place.input, cwd: join(place.root, 'app'), hook_event_name: 'UserPromptSubmit', prompt: 'part999 please' }));
  const [code] = await once(child, 'exit');
  assert.equal(code, 0);
  assert.equal(added(printed.trim(), 'UserPromptSubmit'), 'Relay Everything topic area-19/part999: Summary 999');
});
