import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { connectAi } from '../bin/connect-ai.mjs';
import { record } from '../bin/hook.mjs';
import { ago, saving } from '../bin/saving.mjs';
import { sendSession } from '../lib/send.mjs';
import { fakeServer, project, SESSION } from './fake.mjs';

const bin = name => fileURLToPath(new URL(`../bin/${name}`, import.meta.url));

test('/relay:saving turns a project off and on, and says which it is', () => {
  const place = project();
  assert.deepEqual(saving(place.store, place.root, undefined), [
    'Saving to Relay is on for relay-ring.', 'Each chat here goes to your Relay server as you talk. Type /relay:saving off to stop.',
    'No chat from this project has gone to Relay yet.']);
  assert.deepEqual(saving(place.store, place.root, 'off').slice(0, 2), [
    'Saving to Relay is off for relay-ring.', 'Chats in this project stay on this computer. Type /relay:saving on to save them again.']);
  assert.equal(place.store.isOff(place.root), true);
  assert.equal(saving(place.store, place.root, 'on')[0], 'Saving to Relay is on for relay-ring.');
  assert.equal(place.store.isOff(place.root), false);
  assert.deepEqual(saving(place.store, place.root, 'maybe'), ['Type /relay:saving on, /relay:saving off, or /relay:saving to see which it is.']);
  assert.match(saving(place.store, place.root, undefined, { RELAY_SAVE: '0' }).at(-1), /RELAY_SAVE is 0/);
  // As the skill runs it: in the project, with the data folder.
  const printed = execFileSync(process.execPath, [bin('saving.mjs'), '--data', place.data, 'off'], { cwd: place.root, encoding: 'utf8' });
  assert.match(printed, /^Saving to Relay is off for relay-ring\.\n/);
  assert.equal(place.store.isOff(place.root), true);
});

test('/relay:saving says when the project last sent a chat: the newest send of its sessions, not another project\'s', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  const sentAt = Date.parse('2026-11-05T09:00:00.000Z');
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch, now: () => sentAt }), 'sent');
  assert.equal(place.store.sessions()[SESSION].sentAt, sentAt);
  // A send with nothing new leaves the time as it was.
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch, now: () => sentAt + 1 }), 'sent');
  assert.equal(place.store.sessions()[SESSION].sentAt, sentAt);
  place.store.update('older-session-01', { root: place.root, sentAt: sentAt - 3_600_000 });
  place.store.update('elsewhere-sess-01', { root: place.home, sentAt: sentAt + 60_000 });
  assert.equal(saving(place.store, place.root, undefined, {}, sentAt + 5 * 60_000).at(-1), 'This project last sent a chat to Relay 5 minutes ago.');
  assert.deepEqual([ago(0, 30_000), ago(0, 60_000), ago(0, 3 * 3_600_000), ago(0, 3 * 86_400_000)],
    ['less than a minute ago', '1 minute ago', '3 hours ago', '3 days ago']);
});

test('/relay:connect-ai adds the connector with claude mcp add, and refuses a wrong address', () => {
  const runs = [];
  const ran = (status = 0) => (command, args) => (runs.push([command, ...args]), { status });
  assert.deepEqual(connectAi('https://relay.example.com/mcp', ran()), {
    code: 0, lines: ['Relay is added. Type /mcp, pick relay, and sign in with your Relay email.'] });
  assert.deepEqual(runs, [['claude', 'mcp', 'add', '--transport', 'http', '--scope', 'user', 'relay', 'https://relay.example.com/mcp']]);
  for (const wrong of ['http://relay.example.com/mcp', 'https://relay.example.com', 'https://relay.example.com/mcp/x', 'relay', undefined]) {
    assert.equal(connectAi(wrong, ran()).code, 2, String(wrong));
  }
  assert.equal(runs.length, 1);
  assert.equal(connectAi('https://relay.example.com/mcp', ran(1)).code, 1);
  assert.equal(connectAi('https://relay.example.com/mcp', () => ({ error: new Error('no claude') })).code, 1);
});

test('each skill runs its script with the plugin\'s own folders', () => {
  for (const [skill, script] of [['saving', 'saving.mjs" --data "${CLAUDE_PLUGIN_DATA}"'], ['connect-ai', 'connect-ai.mjs"']]) {
    const text = readFileSync(new URL(`../skills/${skill}/SKILL.md`, import.meta.url), 'utf8');
    assert.match(text, new RegExp(`^---\\nname: ${skill}\\n`));
    assert.ok(text.includes(`node "\${CLAUDE_PLUGIN_ROOT}/bin/${script}`), skill);
  }
});
