// Run with: node --test scripts/relay-knowledge-setup.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { namespaceOf, PAGES, plan, setup } from './relay-knowledge-setup.mjs';
import { parseConfig, repoRoot } from './lib-wrangler-config.mjs';

const ENV = { CLOUDFLARE_API_TOKEN: 'made-up-cloudflare-token', CLOUDFLARE_ACCOUNT_ID: 'acct-made-up' };
const PASS = 'art_v1_made-up-start-pass';
const CONFIG = parseConfig(join(repoRoot, 'app', 'wrangler.relay.jsonc'));

/** Cloudflare's API: each POST makes its thing, or says it is there when `there` names its path's end. */
function fakeCloudflare({ there = [] } = {}) {
  const calls = [];
  const request = async (url, init) => {
    const path = new URL(url).pathname.replace('/client/v4/accounts/acct-made-up/artifacts', '');
    calls.push([init.method, path, init.body && JSON.parse(init.body)]);
    const found = there.some(end => path.endsWith(end)) && init.method === 'POST';
    const result = path.endsWith('/tokens') ? { plaintext: PASS, expires_at: '2026-11-10T12:10:00Z' } : {};
    const json = found ? { success: false, errors: [{ code: 10409, message: 'The namespace already exists.' }] } : { success: true, result };
    return new Response(JSON.stringify(json), { status: found ? 409 : 200 });
  };
  return { calls, request };
}

/** Git that records each call, and finds a change to send unless `unchanged`. */
function fakeGit({ unchanged = false } = {}) {
  const calls = [];
  const git = (args, { cwd, pass }) => {
    calls.push({ args, pass, cwd: Boolean(cwd) });
    return args[0] === 'status' && !unchanged ? 'M  FORMAT.md' : '';
  };
  return { calls, git };
}

test('the namespace comes from the server\'s config, live and staging', () => {
  assert.equal(namespaceOf(CONFIG, false), 'relay-everything-knowledge');
  assert.equal(namespaceOf(CONFIG, true), 'relay-everything-knowledge-staging');
  assert.throws(() => namespaceOf({}, false), /binds no KNOWLEDGE namespace/);
  assert.deepEqual(plan('ns'), ['namespace ns', 'repo start', 'pages README.md, FORMAT.md']);
});

test('makes the namespace and the start repo, and sends the pages with a ten-minute pass kept out of git\'s arguments', async () => {
  const cf = fakeCloudflare();
  const git = fakeGit();
  const lines = await setup({ staging: true, env: ENV, request: cf.request, git: git.git, config: CONFIG });
  assert.deepEqual(lines, ['ok namespace relay-everything-knowledge-staging (made)', 'ok repo start (made)', 'ok pages (sent README.md, FORMAT.md)']);
  assert.deepEqual(cf.calls.map(([method, path]) => `${method} ${path}`), ['POST /namespaces', 'POST /namespaces/relay-everything-knowledge-staging/repos',
    'GET /namespaces/relay-everything-knowledge-staging/repos/start', 'POST /namespaces/relay-everything-knowledge-staging/tokens']);
  assert.deepEqual(cf.calls[3][2], { repo: 'start', scope: 'write', ttl: 600 });
  assert.deepEqual(git.calls.map(call => call.args[0] === '-c' ? call.args[4] : call.args[0]), ['clone', 'checkout', 'add', 'status', 'commit', 'push']);
  assert.equal(git.calls[0].args[2], 'https://acct-made-up.artifacts.cloudflare.net/git/relay-everything-knowledge-staging/start.git');
  assert.deepEqual(git.calls.find(call => call.args[0] === 'add').args, ['add', ...PAGES]);
  assert.ok(git.calls.every(call => call.pass === PASS && !call.args.some(arg => arg.includes(PASS))));
});

test('a second run makes nothing new and sends nothing when the pages are the same', async () => {
  const cf = fakeCloudflare({ there: ['/namespaces', '/repos'] });
  const git = fakeGit({ unchanged: true });
  assert.deepEqual(await setup({ env: ENV, request: cf.request, git: git.git, config: CONFIG }),
    ['ok namespace relay-everything-knowledge (there)', 'ok repo start (there)', 'ok pages (unchanged)']);
  assert.ok(!git.calls.some(call => call.args.includes('push')));
});

test('stops with no Cloudflare key, and on any other Cloudflare refusal', async () => {
  await assert.rejects(setup({ env: {}, config: CONFIG }), /Set CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID/);
  const refused = async () => new Response(JSON.stringify({ success: false, errors: [{ message: 'Artifacts is not on this plan.' }] }), { status: 403 });
  await assert.rejects(setup({ env: ENV, request: refused, git: fakeGit().git, config: CONFIG }), /403 Artifacts is not on this plan\./);
});

test('the website shows the default FORMAT.md word for word', () => {
  const format = readFileSync(join(repoRoot, 'schema', 'knowledge', 'FORMAT.md'), 'utf8');
  const site = readFileSync(join(repoRoot, 'site', 'src', 'content', 'docs', 'api', 'knowledge-web.md'), 'utf8');
  const body = format.replace(/^# .*\n\n/, '');
  assert.ok(site.endsWith(`\n${body}`), 'site/src/content/docs/api/knowledge-web.md must end with schema/knowledge/FORMAT.md, after its title');
});

test('the plugin keeps the default FORMAT.md word for word, to give a web that still has an old default', () => {
  const format = readFileSync(join(repoRoot, 'schema', 'knowledge', 'FORMAT.md'), 'utf8');
  assert.equal(readFileSync(join(repoRoot, 'plugin', 'build', 'FORMAT.md'), 'utf8'), format, 'plugin/build/FORMAT.md must equal schema/knowledge/FORMAT.md');
});
