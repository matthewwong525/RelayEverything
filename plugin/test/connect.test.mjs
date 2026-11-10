import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { test } from 'node:test';
import { claudeEntries, codexEntries, doubles, forget, isRelayEntry, LINK_LIFE, makeVerifier, poll, start, status, wait } from '../bin/connect.mjs';
import { keyFile, readComputer, stateDir } from '../lib/config.mjs';
import { SANDBOX, sandboxed, withSandbox } from '../lib/sandbox.mjs';
import { API, computer, relayHome, SECRET } from './fake.mjs';

const CONNECT = fileURLToPath(new URL('../bin/connect.mjs', import.meta.url));
const run = promisify(execFile);
const answer = (status, json) => new Response(JSON.stringify(json), { status, headers: { 'content-type': 'application/json' } });
const pending = env => JSON.parse(readFileSync(join(stateDir(env), 'connect.json'), 'utf8'));
const KEY_ANSWER = { server: 'https://relay.example.com', key: SECRET, api: API, name: 'Laptop' };

/** A sign-in server: start gives a link and a code; the key route says wait `waits` times, then gives the key once. */
function signIn({ waits = 0, startStatus = 200, keyStatus } = {}) {
  const calls = [];
  let given = false;
  const fetcher = async (url, init) => {
    const body = JSON.parse(init.body);
    calls.push({ url, body });
    if (url.endsWith('/computer/start')) {
      return startStatus === 200 ? answer(200, { link: 'https://relay.example.com/apps/relay/sign-in/computer?c=made-up', words: 'maple-river-stone' })
        : answer(startStatus, { error: 'nope' });
    }
    if (keyStatus) return answer(keyStatus, { error: 'gone' });
    if (waits-- > 0) return answer(202, { waiting: true });
    if (given) return answer(400, { error: 'used' });
    given = true;
    return answer(200, KEY_ANSWER);
  };
  return { calls, fetcher };
}

test('the verifier is 43 base64url characters, and the challenge is its SHA-256 in the same shape', () => {
  const { verifier, challenge } = makeVerifier();
  assert.match(verifier, /^[A-Za-z0-9_-]{43}$/);
  assert.match(challenge, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(makeVerifier().verifier, verifier);
});

test('start sends only the challenge and the name, shows the link and the code, and keeps the secret private', async () => {
  const env = relayHome({ connected: false });
  const server = signIn();
  const waiters = [];
  const done = await start('https://relay.example.com/', { env, fetcher: server.fetcher, waiter: (...args) => waiters.push(args), name: 'A'.repeat(80), now: () => 1000 });
  assert.equal(done.code, 0);
  assert.deepEqual(done.lines, [
    'Open this link on any phone or computer: https://relay.example.com/apps/relay/sign-in/computer?c=made-up',
    'Check that the page shows this code: maple-river-stone',
    'Then click Connect. The link works for 10 minutes, once.']);
  const [call] = server.calls;
  assert.equal(call.url, 'https://relay.example.com/apps/relay/sign-in/computer/start');
  assert.deepEqual(Object.keys(call.body).sort(), ['challenge', 'name']);
  assert.equal(call.body.name, 'A'.repeat(60));
  const kept = pending(env);
  assert.equal(makeVerifierCheck(kept.verifier), call.body.challenge);
  assert.equal(statSync(join(stateDir(env), 'connect.json')).mode & 0o777, 0o600);
  assert.deepEqual(waiters, [[env, 1000]]);
  assert.ok(!done.lines.join('\n').includes(kept.verifier));
});

// The challenge the server gets is the SHA-256 of the kept secret.
const makeVerifierCheck = verifier => createHash('sha256').update(verifier).digest('base64url');

test('start says what went wrong: a wrong address, too many tries, no answer, or not a Relay Everything server', async () => {
  const env = relayHome({ connected: false });
  const nothing = () => {};
  for (const wrong of ['http://relay.example.com', 'https://relay.example.com/apps', 'relay']) {
    assert.equal((await start(wrong, { env, fetcher: signIn().fetcher, waiter: nothing })).code, 2, wrong);
  }
  assert.match((await start('', { env, fetcher: signIn({ startStatus: 429 }).fetcher, waiter: nothing })).lines[0], /too many tries/);
  assert.match((await start('', { env, fetcher: signIn({ startStatus: 404 }).fetcher, waiter: nothing })).lines[0],
    /^https:\/\/app\.relayeverything\.com did not answer as a Relay Everything server does/);
  const down = async () => { throw new TypeError('fetch failed'); };
  assert.match((await start('https://relay.example.com', { env, fetcher: down, waiter: nothing })).lines[0], /could not be reached\. Check the address and the network, then try again\.$/);
  assert.equal(existsSync(join(stateDir(env), 'connect.json')), false);
  // In Codex's sandbox, the name lookup fails: the line names the sandbox, not only the address.
  const sandbox = async () => { throw Object.assign(new TypeError('fetch failed'), { cause: Object.assign(new Error('getaddrinfo EAI_AGAIN'), { code: 'EAI_AGAIN' }) }); };
  assert.match((await start('', { env, fetcher: sandbox, waiter: nothing })).lines[0], /could not be reached\. .* If this runs in a sandbox, such as Codex's, run the command again outside the sandbox\.$/);
});

test('start says when it can not write its folder, and names a sandbox for a read-only one', async () => {
  const parent = mkdtempSync(join(tmpdir(), 'relay-file-'));
  writeFileSync(join(parent, 'file'), '');
  const env = { RELAY_EVERYTHING_HOME: join(parent, 'file', 'relay-everything') };
  const waiters = [];
  const done = await start('', { env, fetcher: signIn().fetcher, waiter: (...args) => waiters.push(args) });
  assert.deepEqual(done, { code: 1, lines: [`The folder ${env.RELAY_EVERYTHING_HOME} could not be written, so this computer can not keep its key.`] });
  assert.deepEqual(waiters, []);
  assert.equal(withSandbox('A line.', Object.assign(new Error('read-only'), { code: 'EROFS' })), `A line. ${SANDBOX}`);
  assert.equal(withSandbox('A line.', Object.assign(new Error('no folder'), { code: 'ENOTDIR' })), 'A line.');
  assert.equal(sandboxed(undefined), false);
});

test('the waiter asks until Connect, keeps the key in a private file, and wait names the computer', async () => {
  const env = relayHome({ connected: false });
  const server = signIn({ waits: 2 });
  await start('https://relay.example.com', { env, fetcher: server.fetcher, waiter: () => {}, now: () => Date.now() });
  const { startedAt } = pending(env);
  // A lost answer is asked again on the next round.
  let lost = 1;
  const flaky = async (url, init) => { if (lost-- > 0) throw new TypeError('fetch failed'); return server.fetcher(url, init); };
  assert.equal(await poll(startedAt, { env, fetcher: flaky, every: 1 }), 'connected');
  assert.deepEqual(server.calls.slice(1).map(call => Object.keys(call.body)), [['verifier'], ['verifier'], ['verifier']]);
  assert.deepEqual(readComputer(env), KEY_ANSWER);
  assert.equal(statSync(keyFile(env)).mode & 0o777, 0o600);
  assert.ok(!JSON.stringify(pending(env)).includes(SECRET));
  const done = await wait({ env, run: () => ({ status: 1, stdout: '' }) });
  assert.deepEqual(done, { code: 0, lines: ['Relay Everything is connected as "Laptop", at https://relay.example.com.'] });
  assert.equal(existsSync(join(stateDir(env), 'connect.json')), false);
  // In Codex, it also says that the hooks need trust.
  assert.match((await wait({ env: { ...env, CODEX_THREAD_ID: 'thread' } })).lines.join('\n'), /connected as "Laptop"/);
});

test('a link that is gone, too old, replaced, or a key that is not one, ends the waiter with a reason', async () => {
  const env = relayHome({ connected: false });
  const nothing = () => {};
  await start('https://relay.example.com', { env, fetcher: signIn().fetcher, waiter: nothing });
  assert.equal(await poll(pending(env).startedAt, { env, fetcher: signIn({ keyStatus: 400 }).fetcher, every: 1 }), 'expired');
  assert.deepEqual(await wait({ env }), { code: 1, lines: ['Nobody clicked Connect in time, so no key was made. Type /relay:connect to start again.'] });
  let clock = 0;
  await start('https://relay.example.com', { env, fetcher: signIn().fetcher, waiter: nothing, now: () => clock });
  assert.equal(await poll(0, { env, fetcher: signIn({ waits: 99 }).fetcher, every: 1, now: () => (clock += 4 * 60_000) }), 'expired');
  await start('https://relay.example.com', { env, fetcher: signIn().fetcher, waiter: nothing, now: () => 5 });
  assert.equal(await poll(4, { env, fetcher: signIn().fetcher, every: 1, now: () => 5 }), 'replaced');
  const bad = async url => (url.endsWith('/start') ? signIn().fetcher(url, { body: '{}' }) : answer(200, { ...KEY_ANSWER, key: 'not-a-key' }));
  await start('https://relay.example.com', { env, fetcher: bad, waiter: nothing, now: () => Date.now() });
  assert.equal(await poll(pending(env).startedAt, { env, fetcher: bad, every: 1 }), 'failed');
  assert.match((await wait({ env })).lines[0], /can not use/);
  assert.equal(readComputer(env), null);
});

test('wait stops after its limit while the person has not clicked Connect', async () => {
  const env = relayHome({ connected: false });
  await start('https://relay.example.com', { env, fetcher: signIn().fetcher, waiter: () => {}, now: () => Date.now() });
  assert.deepEqual(await wait({ env, limit: 20, every: 5 }), { code: 3, lines: ['Not connected yet. When you have clicked Connect, ask me to check again.'] });
  assert.match(status(env).lines[1], /^A sign-in link is waiting for Connect, with the code maple-river-stone\.$/);
  assert.deepEqual(await wait({ env: relayHome({ connected: false }) }), { code: 1, lines: ['No sign-in link is waiting. Type /relay:connect to start one.'] });
});

test('wait says the link ended when the waiter died and left it waiting past its 10 minutes', async () => {
  const env = relayHome({ connected: false });
  await start('https://relay.example.com', { env, fetcher: signIn().fetcher, waiter: () => {}, now: () => 1_000 });
  assert.equal(pending(env).result, 'waiting');
  assert.deepEqual(await wait({ env, now: () => 1_000 + LINK_LIFE }), { code: 1,
    lines: ['The sign-in link ended before this computer got its key. Type /relay:connect to start again.'] });
  assert.equal(existsSync(join(stateDir(env), 'connect.json')), false);
  assert.deepEqual(await wait({ env }), { code: 1, lines: ['No sign-in link is waiting. Type /relay:connect to start one.'] });
});

test('wait still answers when its folder can not be written, and a command line prints one line, not a stack', async () => {
  const readOnly = () => { throw Object.assign(new Error('read-only file system'), { code: 'EROFS' }); };
  const env = relayHome({ connected: false });
  const server = signIn();
  await start('https://relay.example.com', { env, fetcher: server.fetcher, waiter: () => {}, now: () => Date.now() });
  assert.equal(await poll(pending(env).startedAt, { env, fetcher: server.fetcher, every: 1 }), 'connected');
  const connected = { code: 0, lines: ['Relay Everything is connected as "Laptop", at https://relay.example.com.'] };
  assert.deepEqual(await wait({ env, run: () => ({ status: 1 }), remove: readOnly }), connected);
  // The answer file stays, so the next wait says the same.
  assert.equal(pending(env).result, 'connected');
  assert.deepEqual(await wait({ env, run: () => ({ status: 1 }), remove: readOnly }), connected);
  await start('https://relay.example.com', { env, fetcher: signIn().fetcher, waiter: () => {}, now: () => 1_000 });
  assert.match((await wait({ env, now: () => 1_000 + LINK_LIFE, remove: readOnly })).lines[0], /^The sign-in link ended/);
  // A file where the folder should be: forget's delete fails, as it does in a read-only sandbox.
  const parent = mkdtempSync(join(tmpdir(), 'relay-file-'));
  writeFileSync(join(parent, 'file'), '');
  const blocked = { ...process.env, RELAY_EVERYTHING_HOME: join(parent, 'file', 'relay-everything') };
  const failed = await run(process.execPath, [CONNECT, 'forget'], { env: blocked }).then(() => null, error => error);
  assert.equal(failed.code, 1);
  assert.equal(failed.stdout, 'Relay Everything could not finish this step on this computer. Try again in a minute.\n');
  assert.equal(failed.stderr, '');
});

test('status and forget say what this computer has, and forget deletes only the key file', () => {
  const env = relayHome();
  assert.deepEqual(status(env), { code: 0, lines: ['Relay Everything is connected as "Laptop", at https://relay.example.com.'] });
  assert.match(forget(env).lines[0], /^This computer no longer has its Relay Everything key\. .*Devices.*Turn off\.$/);
  assert.equal(existsSync(keyFile(env)), false);
  assert.equal(existsSync(join(keyFile(env), '..')), true);
  assert.equal(forget(env).lines[0], 'This computer had no Relay Everything key.');
  assert.equal(status(env).code, 1);
});

// What `claude mcp list` prints, made up: two Relay Everything entries by name, one by its host, and two others.
const CLAUDE_LIST = `Checking MCP server health...

relay: ${API.replace('/v1', '')}/mcp (HTTP) - ✓ Connected
local-tool: node /opt/tool/server.js - ✓ Connected
claude.ai Relay Everything: https://mcp.relayeverything.com/mcp (HTTP) - ! Needs authentication
notes copy: https://connector.example.com/mcp (HTTP) - ✗ Failed to connect
claude.ai Calendar: https://calendar.example.org/mcp (HTTP) - ✓ Connected
`;
const CODEX_LIST = JSON.stringify([
  { name: 'relay-everything', transport: { type: 'streamable_http', url: 'https://mcp.relayeverything.com/mcp' } },
  { name: 'other', transport: { type: 'stdio', command: 'node' } },
]);

test('finds each Relay Everything connector by its name or host, and names its remove command', () => {
  assert.deepEqual(claudeEntries(CLAUDE_LIST).map(entry => entry.name),
    ['relay', 'local-tool', 'claude.ai Relay Everything', 'notes copy', 'claude.ai Calendar']);
  assert.equal(claudeEntries(CLAUDE_LIST)[1].address, 'node /opt/tool/server.js');
  assert.deepEqual(codexEntries(CODEX_LIST).map(entry => entry.address), ['https://mcp.relayeverything.com/mcp', '']);
  assert.deepEqual(codexEntries('not json'), []);
  assert.equal(isRelayEntry('Relay', '', null), true);
  assert.equal(isRelayEntry('relay-ring-tool', 'node', null), false);
  assert.equal(isRelayEntry('x', 'https://MCP.relayeverything.com/mcp', null), true);
  assert.equal(isRelayEntry('x', 'https://connector.example.com/mcp', computer()), true);
  assert.equal(isRelayEntry('x', 'https://connector.example.com/mcp', null), false);
  const runs = [];
  const answers = {
    'claude mcp list': CLAUDE_LIST,
    'claude mcp get relay': 'relay:\n  Scope: User config (available in all your projects)\n',
    'claude mcp get notes copy': 'notes copy:\n  Scope: Local config (private to you in this project)\n',
    'codex mcp list --json': CODEX_LIST,
  };
  const fake = (command, args) => {
    const line = [command, ...args].join(' ');
    runs.push(line);
    return line in answers ? { status: 0, stdout: answers[line] } : { status: 1, stdout: '' };
  };
  const lines = doubles(computer(), fake);
  assert.equal(lines.length, 4);
  assert.match(lines[0], /\("relay"\)\. .*: claude mcp remove relay -s user$/);
  assert.match(lines[1], /from your Claude account \("claude\.ai Relay Everything"\)\. .*type \/mcp in Claude Code/);
  assert.match(lines[2], /: claude mcp remove 'notes copy' -s local$/);
  assert.match(lines[3], /^Codex also has .*: codex mcp remove relay-everything$/);
  // It only lists and reads: it never removes.
  assert.ok(runs.every(line => !/\bremove\b/.test(line)));
  // With neither app, or with a broken list, it says nothing.
  assert.deepEqual(doubles(computer(), () => ({ error: new Error('ENOENT') })), []);
});

test('connects from the command line against a local server, then names the doubles from claude and codex on PATH', async () => {
  const signIns = [];
  const server = createServer((request, response) => {
    let body = '';
    request.on('data', part => { body += part; });
    request.on('end', () => {
      signIns.push(request.url);
      const json = request.url.endsWith('/start') ? { link: 'http://127.0.0.1/link', words: 'made-up-words' } : KEY_ANSWER;
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify(json));
    });
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const bin = mkdtempSync(join(tmpdir(), 'relay-bin-'));
  const log = join(bin, 'ran.log');
  for (const [name, list] of [['claude', CLAUDE_LIST], ['codex', CODEX_LIST]]) {
    writeFileSync(join(bin, name), `#!/usr/bin/env node
require('node:fs').appendFileSync(${JSON.stringify(log)}, ${JSON.stringify(name)} + ' ' + process.argv.slice(2).join(' ') + '\\n');
const args = process.argv.slice(2).join(' ');
if (args === 'mcp list' || args === 'mcp list --json') process.stdout.write(${JSON.stringify(list)});
else if (args.startsWith('mcp get')) process.stdout.write('Scope: User config\\n');
else process.exit(1);
`);
    chmodSync(join(bin, name), 0o755);
  }
  mkdirSync(join(bin, 'home'));
  const env = { ...process.env, ...relayHome({ connected: false }), PATH: `${bin}:${process.env.PATH}` };
  try {
    const started = await run(process.execPath, [CONNECT, 'start', `http://127.0.0.1:${server.address().port}`], { env });
    assert.match(started.stdout, /^Open this link on any phone or computer: http:\/\/127\.0\.0\.1\/link\nCheck that the page shows this code: made-up-words\n/);
    const waited = await run(process.execPath, [CONNECT, 'wait'], { env });
    const lines = waited.stdout.trim().split('\n');
    assert.equal(lines[0], 'Relay Everything is connected as "Laptop", at https://relay.example.com.');
    assert.equal(lines.length, 5);
    assert.ok(!waited.stdout.includes(SECRET));
    assert.deepEqual(signIns, ['/apps/relay/sign-in/computer/start', '/apps/relay/sign-in/computer/key']);
    const ran = readFileSync(log, 'utf8').trim().split('\n');
    assert.ok(ran.includes('claude mcp list') && ran.includes('codex mcp list --json'));
    assert.ok(ran.every(line => !line.includes('remove')), 'nothing is removed');
    assert.match((await run(process.execPath, [CONNECT, 'status'], { env })).stdout, /^Relay Everything is connected as "Laptop"/);
  } finally {
    server.close();
  }
});
