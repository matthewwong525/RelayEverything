import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { copyOf, EVERY, knowledge, NO_GIT, NOT_SET_UP, status, sync } from '../bin/knowledge.mjs';
import { NOT_CONNECTED } from '../bin/relay.mjs';
import { relayHome, SECRET } from './fake.mjs';

const PASS = 'art_v1_made-up-pass-for-a-test';
const MINUTE = 60_000;
const git = (args, cwd) => execFileSync('git', ['-c', 'user.name=Test', '-c', 'user.email=test@localhost', ...args], { cwd, encoding: 'utf8' }).trim();

/** A bare repo standing in for the person's web in Artifacts, holding the two start pages. */
function web() {
  const root = mkdtempSync(join(tmpdir(), 'relay-web-'));
  const start = join(root, 'start');
  mkdirSync(start);
  git(['init', '--quiet', '-b', 'main'], start);
  writeFileSync(join(start, 'README.md'), '# Topics\n');
  writeFileSync(join(start, 'FORMAT.md'), '# The rules\n');
  git(['add', '-A'], start);
  git(['commit', '--quiet', '-m', 'Start'], start);
  const bare = join(root, 'p-ana.git');
  git(['clone', '--quiet', '--bare', start, bare], root);
  return bare;
}

/** The pass route: the web's address and a pass, or the status it is told to answer. */
function passes(remote, status = 200) {
  const calls = [];
  const fetcher = async (url, init) => {
    calls.push({ url, method: init.method, auth: init.headers.Authorization, body: init.body });
    const json = status === 200 ? { remote, token: PASS, expiresAt: '2026-11-10T13:00:00.000Z' }
      : { error: status === 501 ? 'not_set_up' : 'forbidden', error_description: 'A made-up refusal.' };
    return new Response(JSON.stringify(json), { status, headers: { 'content-type': 'application/json' } });
  };
  return { calls, fetcher };
}

const files = dir => readdirSync(dir, { withFileTypes: true, recursive: true }).filter(entry => entry.isFile())
  .map(entry => join(entry.parentPath, entry.name));

test('the first sync gets the web, a sync within 15 minutes makes no call, and a change or --now syncs anyway', async () => {
  const remote = web();
  const server = passes(remote);
  const env = relayHome();
  let clock = Date.UTC(2026, 10, 10, 12);
  const run = (now = false) => sync({ env, fetcher: server.fetcher, now, clock: () => clock });
  assert.deepEqual(await run(), { code: 0, lines: [`Your knowledge web is synced in ${copyOf(env)}.`] });
  assert.deepEqual(readdirSync(copyOf(env)).sort(), ['.git', 'FORMAT.md', 'README.md']);
  assert.deepEqual(server.calls, [{ url: 'https://connector.example.com/v1/knowledge/access', method: 'POST', auth: `Bearer ${SECRET}`, body: '{}' }]);
  clock += 5 * MINUTE;
  assert.match((await run()).lines[0], /is new enough: it synced 5 minutes ago\.$/);
  assert.equal(server.calls.length, 1);
  writeFileSync(join(copyOf(env), 'README.md'), '# Topics\n\n- [Battery](topics/battery.md): the ring\'s battery.\n');
  assert.equal((await run()).code, 0);
  assert.equal(server.calls.length, 2);
  assert.match(git(['show', 'main:README.md'], remote), /Battery/);
  clock += MINUTE;
  assert.equal((await run(true)).code, 0);
  assert.equal(server.calls.length, 3);
  clock += EVERY;
  await run();
  assert.equal(server.calls.length, 4);
  // The pass reaches no file, in the copy, its git folder or the Relay Everything folder, and not the remote.
  assert.deepEqual(files(env.RELAY_EVERYTHING_HOME).filter(path => readFileSync(path).includes(PASS)), []);
  assert.equal(git(['remote', 'get-url', 'origin'], copyOf(env)), remote);
});

test('two computers each write a different page, and each gets both; a page both change keeps both versions', async () => {
  const remote = web();
  const server = passes(remote);
  const [laptop, desktop] = [relayHome(), relayHome()];
  const run = env => sync({ env, fetcher: server.fetcher, now: true });
  await run(laptop);
  await run(desktop);
  mkdirSync(join(copyOf(laptop), 'topics'));
  mkdirSync(join(copyOf(desktop), 'topics'));
  writeFileSync(join(copyOf(laptop), 'topics', 'battery.md'), 'The battery is 50 mAh.\n');
  writeFileSync(join(copyOf(desktop), 'topics', 'sam.md'), 'Sam builds the case.\n');
  assert.equal((await run(laptop)).code, 0);
  assert.equal((await run(desktop)).code, 0);
  assert.equal((await run(laptop)).code, 0);
  for (const env of [laptop, desktop]) assert.deepEqual(readdirSync(join(copyOf(env), 'topics')).sort(), ['battery.md', 'sam.md']);
  writeFileSync(join(copyOf(laptop), 'README.md'), '# Topics\n- Battery\n');
  writeFileSync(join(copyOf(desktop), 'README.md'), '# Topics\n- Sam\n');
  assert.equal((await run(laptop)).code, 0);
  assert.equal((await run(desktop)).code, 0);
  assert.equal((await run(laptop)).code, 0);
  for (const env of [laptop, desktop]) {
    const page = readFileSync(join(copyOf(env), 'README.md'), 'utf8');
    assert.ok(page.includes('- Battery') && page.includes('- Sam') && !page.includes('<<<<<<<'), page);
  }
});

test('git gets the pass as a header for clone, fetch and push, and for no other command', async () => {
  // A git in front of the real one writes each command and the header it was given, then runs the real git.
  const real = execFileSync('sh', ['-c', 'command -v git'], { encoding: 'utf8' }).trim();
  const bin = mkdtempSync(join(tmpdir(), 'relay-git-'));
  const log = join(bin, 'calls.log');
  writeFileSync(join(bin, 'git'), `#!/bin/sh\nfor arg in "$@"; do case "$arg" in -c|user.*) ;; *) printf '%s\\t%s\\n' "$arg" "$GIT_CONFIG_VALUE_0" >> '${log}'; break;; esac; done\nexec '${real}' "$@"\n`);
  chmodSync(join(bin, 'git'), 0o755);
  const remote = web();
  const env = relayHome();
  const path = process.env.PATH;
  // Only the syncs run with the recording git, not this test's own git commands.
  const run = async () => {
    process.env.PATH = `${bin}:${path}`;
    try {
      return await sync({ env, fetcher: passes(remote).fetcher, now: true });
    } finally {
      process.env.PATH = path;
    }
  };
  assert.equal((await run()).code, 0);
  writeFileSync(join(copyOf(env), 'README.md'), '# Topics\n- Battery\n');
  assert.equal((await run()).code, 0);
  assert.match(git(['show', 'main:README.md'], remote), /Battery/);
  const calls = readFileSync(log, 'utf8').trim().split('\n').map(line => line.split('\t'));
  const header = `Authorization: Bearer ${PASS}`;
  for (const command of ['clone', 'fetch', 'push']) {
    assert.ok(calls.some(([name]) => name === command), `git ${command} ran`);
    assert.ok(calls.filter(([name]) => name === command).every(([, sent]) => sent === header), `git ${command} got the pass`);
  }
  assert.deepEqual(calls.filter(([name]) => !['clone', 'fetch', 'push'].includes(name)).filter(([, sent]) => sent), []);
});

test('a file both copies change that lines can not join keeps this copy\'s version, and the web\'s as <name>.other', async () => {
  const remote = web();
  const server = passes(remote);
  const [laptop, desktop] = [relayHome(), relayHome()];
  const run = env => sync({ env, fetcher: server.fetcher, now: true });
  const picture = (env, byte) => writeFileSync(join(copyOf(env), 'ring.png'), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 0, byte]));
  await run(laptop);
  picture(laptop, 1);
  assert.equal((await run(laptop)).code, 0);
  await run(desktop);
  picture(laptop, 2);
  picture(desktop, 3);
  assert.equal((await run(laptop)).code, 0);
  assert.deepEqual(await run(desktop), { code: 0, lines: [`Your knowledge web is synced in ${copyOf(desktop)}.`] });
  assert.deepEqual([...readFileSync(join(copyOf(desktop), 'ring.png'))].at(-1), 3);
  assert.deepEqual([...readFileSync(join(copyOf(desktop), 'ring.png.other'))].at(-1), 2);
  assert.equal(git(['status', '--porcelain'], copyOf(desktop)), '');
  assert.ok(git(['ls-tree', '--name-only', 'main'], remote).split('\n').includes('ring.png.other'));
});

test('says when the server has no web, refuses the key, is not connected, or the computer has no git', async () => {
  const env = relayHome();
  const run = (status, more = {}) => sync({ env, fetcher: passes('/nowhere', status).fetcher, ...more });
  assert.deepEqual(await run(501), { code: 1, lines: [NOT_SET_UP] });
  assert.deepEqual(await run(403), { code: 1,
    lines: ['Relay Everything refused this computer\'s key: A made-up refusal. Type /relay:connect to connect again.'] });
  assert.deepEqual(await run(200, { env: relayHome({ connected: false }) }), { code: 1, lines: [NOT_CONNECTED] });
  const offline = passes('/nowhere');
  assert.deepEqual(await sync({ env: { ...env, PATH: join(tmpdir(), 'no-git-here') }, fetcher: offline.fetcher }), { code: 1, lines: [NO_GIT] });
  assert.equal(offline.calls.length, 0);
  assert.deepEqual(await knowledge(['pull']), { code: 2, lines: ['Commands: sync [--now], status.'] });
});

test('status says where the copy is, when it synced, and whether it has changes, with no call', async () => {
  const env = relayHome();
  assert.match(status({ env }).lines[0], /no copy of your knowledge web yet/);
  const clock = Date.UTC(2026, 10, 10, 12);
  await sync({ env, fetcher: passes(web()).fetcher, clock: () => clock });
  writeFileSync(join(copyOf(env), 'FORMAT.md'), '# My rules\n');
  assert.deepEqual(status({ env, clock: () => clock + 3 * MINUTE }).lines, [`Your knowledge web is in ${copyOf(env)}.`,
    'It last synced 3 minutes ago.', 'It has changes that the next sync sends.']);
});
