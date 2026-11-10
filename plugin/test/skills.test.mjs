import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { record } from '../bin/hook.mjs';
import { ago, run, saving } from '../bin/saving.mjs';
import { forgetComputer, readState } from '../lib/config.mjs';
import { sendSession } from '../lib/send.mjs';
import { fakeServer, project, SESSION } from './fake.mjs';

const bin = name => fileURLToPath(new URL(`../bin/${name}`, import.meta.url));
const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('/relay:saving turns a project off and on, and says which it is', () => {
  const place = project();
  const say = (choice, env = place.env) => saving(place.store, place.root, choice, env);
  assert.deepEqual(say(undefined), [
    'Saving to Relay Everything is on for relay-ring.',
    'Each chat here goes to your Relay Everything server as you talk, from Claude Code or Codex. Type /relay:saving off to stop.',
    'No chat from this project has gone to Relay Everything yet.']);
  assert.deepEqual(say('off').slice(0, 2), [
    'Saving to Relay Everything is off for relay-ring.', 'Chats in this project stay on this computer. Type /relay:saving on to save them again.']);
  assert.equal(place.store.isOff(place.root), true);
  assert.equal(say('on')[0], 'Saving to Relay Everything is on for relay-ring.');
  assert.equal(place.store.isOff(place.root), false);
  assert.deepEqual(say('maybe'), ['Type /relay:saving on, /relay:saving off, or /relay:saving to see which it is.']);
  assert.match(say(undefined, { ...place.env, RELAY_SAVE: '0' }).at(-1), /RELAY_SAVE is 0/);
  forgetComputer(place.env);
  assert.equal(say(undefined).at(-1), 'This computer is not connected, so no chat is saved now. Type /relay:connect to connect it.');
  // As the skill runs it: in the project, with the Relay Everything folder from the env.
  const printed = execFileSync(process.execPath, [bin('saving.mjs'), 'off'], { cwd: place.root, env: { ...process.env, ...place.env }, encoding: 'utf8' });
  assert.match(printed, /^Saving to Relay Everything is off for relay-ring\.\n/);
  assert.equal(place.store.isOff(place.root), true);
});

test('/relay:saving only looks where it can not write, and says so when asked to change', () => {
  const place = project();
  place.store.setOff(place.root, true);
  // A look reads the state with no folder made or changed.
  assert.equal(saving(readState(place.env), place.root, undefined, place.env)[0], 'Saving to Relay Everything is off for relay-ring.');
  // A file where the folder should be: openState fails, as it does in a read-only sandbox.
  const env = { RELAY_EVERYTHING_HOME: join(place.transcript, 'relay-everything') };
  const look = run(undefined, { env, cwd: place.root });
  assert.equal(look.code, 0);
  assert.equal(look.lines[0], 'Saving to Relay Everything is on for relay-ring.');
  assert.equal(run('maybe', { env, cwd: place.root }).lines[0], 'Type /relay:saving on, /relay:saving off, or /relay:saving to see which it is.');
  assert.deepEqual(run('off', { env, cwd: place.root }), { code: 1,
    lines: [`The folder ${env.RELAY_EVERYTHING_HOME} could not be written, so saving did not change.`] });
  assert.equal(run('on', { env: place.env, cwd: place.root }).code, 0);
  assert.equal(place.store.isOff(place.root), false);
});

test('/relay:saving says when the project last sent a chat: the newest send of its sessions, not another project\'s', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  const sentAt = Date.now();
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch, now: () => sentAt }), 'sent');
  assert.equal(place.store.sessions()[SESSION].sentAt, sentAt);
  // A send with nothing new leaves the time as it was.
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch, now: () => sentAt + 1 }), 'sent');
  assert.equal(place.store.sessions()[SESSION].sentAt, sentAt);
  place.store.update('older-session-01', { root: place.root, sentAt: sentAt - 3_600_000, seen: sentAt });
  place.store.update('elsewhere-sess-01', { root: place.home, sentAt: sentAt + 60_000, seen: sentAt });
  assert.equal(saving(place.store, place.root, undefined, place.env, sentAt + 5 * 60_000).at(-1), 'This project last sent a chat to Relay Everything 5 minutes ago.');
  assert.deepEqual([ago(0, 30_000), ago(0, 60_000), ago(0, 3 * 3_600_000), ago(0, 3 * 86_400_000)],
    ['less than a minute ago', '1 minute ago', '3 hours ago', '3 days ago']);
});

test('each skill names itself and runs its own script from the plugin\'s folder', () => {
  for (const [skill, script] of [['connect', 'connect.mjs'], ['ask', 'relay.mjs'], ['save', 'save.mjs'], ['saving', 'saving.mjs']]) {
    const text = read(`skills/${skill}/SKILL.md`);
    assert.match(text, new RegExp(`^---\\nname: ${skill}\\ndescription: .*Relay Everything`), skill);
    assert.ok(text.includes(`node "\${CLAUDE_PLUGIN_ROOT}/bin/${script}"`), skill);
    assert.ok(text.includes('In Codex it is empty: use the folder two levels above this file'), skill);
    assert.ok(text.includes('**In Codex, run each command here outside the sandbox.** Ask for escalated permissions'), skill);
    assert.ok(text.length < 4000, `${skill} stays short`);
  }
  assert.match(read('skills/ask/SKILL.md'), /this computer's time zone/);
  assert.ok(read('skills/save/SKILL.md').includes('--session "${CLAUDE_SESSION_ID}"'));
});

test('the hooks run in Claude Code and Codex: no async hook, a short end, and the plugin\'s folder in each command', () => {
  const { hooks } = JSON.parse(read('hooks/hooks.json'));
  assert.deepEqual(Object.keys(hooks), ['SessionStart', 'Stop', 'SessionEnd']);
  const events = { SessionStart: 'session-start', Stop: 'stop', SessionEnd: 'session-end' };
  for (const [event, groups] of Object.entries(hooks)) {
    const [hook] = groups.flatMap(group => group.hooks);
    assert.equal(hook.async, undefined, `${event}: Codex does not run an async hook`);
    assert.equal(hook.command, `node "\${CLAUDE_PLUGIN_ROOT}/bin/hook.mjs" ${events[event]}`);
  }
  assert.equal(hooks.SessionEnd[0].hooks[0].timeout, 3);
  const manifest = JSON.parse(read('.claude-plugin/plugin.json'));
  assert.equal(manifest.version, '0.3.0');
  assert.equal(manifest.userConfig, undefined);
  assert.match(manifest.description, /Claude Code/);
  assert.match(manifest.description, /Codex/);
});
