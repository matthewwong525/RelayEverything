// Run with: node --test self-host/
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { accessApp, bypassPolicy, configs, keysApp, names, PARTS, parseCommand, settingsOf, setup } from './setup.mjs';

const TOKEN = 'test-token-never-printed-0123456789';
const ACCOUNT = 'a'.repeat(32);
const template = file => readFileSync(join(import.meta.dirname, file), 'utf8');
const files = () => {
  const dir = mkdtempSync(join(tmpdir(), 'relay-self-host-'));
  return { config: join(dir, 'wrangler.jsonc'), mcp: join(dir, 'wrangler.mcp.jsonc'), spaces: join(dir, 'wrangler.spaces.jsonc') };
};

/** Cloudflare's API as a test answers it: `answers` maps "METHOD path" to a result, or to a status to fail with. */
function fakeCloudflare(answers) {
  const calls = [];
  const request = async (url, init) => {
    const key = `${init.method} ${new URL(url).pathname.replace(/^\/client\/v4/, '')}`;
    calls.push(key);
    const answer = answers[key] ?? 404;
    return typeof answer === 'number'
      ? new Response(JSON.stringify({ success: false, errors: [{ message: 'no' }] }), { status: answer })
      : new Response(JSON.stringify({ success: true, result: answer }));
  };
  return { request, calls };
}
const run = async (args, answers, more = {}) => {
  const lines = [];
  const wrangler = more.wrangler ?? (() => {});
  const { request, calls } = fakeCloudflare(answers);
  const result = await setup({ args, env: { CLOUDFLARE_API_TOKEN: TOKEN, CLOUDFLARE_ACCOUNT_ID: ACCOUNT }, request, wrangler,
    build: () => lines.push('built'), log: line => lines.push(line), files: more.files ?? files() });
  return { result, lines, calls, output: lines.join('\n') };
};
const everyPart = Object.fromEntries(PARTS.map(([, path]) => [`GET /accounts/${ACCOUNT}${path}`, path.includes('organizations') ? { auth_domain: 'you.cloudflareaccess.com' } : []]));

test('the commands take a name and the owner\'s email, and refuse a bad one', () => {
  assert.deepEqual(parseCommand(['install', '--email', 'you@example.com']), { command: 'install', name: 'relay', email: 'you@example.com', yes: false });
  assert.match(parseCommand(['install']).problem, /--email/);
  assert.match(parseCommand(['status', '--name', 'Relay!']).problem, /--name/);
  assert.match(parseCommand(['deploy']).problem, /name a command/);
});

test('check names each missing permission and part, makes nothing, and never prints the token', async () => {
  const answers = { ...everyPart, [`GET /accounts/${ACCOUNT}/r2/buckets`]: 403, [`GET /accounts/${ACCOUNT}/queues`]: 403,
    [`GET /accounts/${ACCOUNT}/access/organizations`]: 404 };
  const install = await run(['install', '--email', 'you@example.com'], answers);
  assert.equal(install.result, 'refused');
  assert.match(install.output, /missing R2 bucket: add "Workers R2 Storage Write" to the token/);
  assert.match(install.output, /missing Queues: add "Queues Write"/);
  assert.match(install.output, /missing Zero Trust: turn on Zero Trust/);
  assert.ok(install.calls.every(call => call.startsWith('GET ')), 'a refused install makes nothing');
  assert.doesNotMatch(install.output, new RegExp(TOKEN));
  assert.equal((await run(['check'], everyPart)).result, 'ok');
});

const templates = { app: template('wrangler.template.jsonc'), mcp: template('mcp.template.jsonc'), spaces: template('spaces.template.jsonc') };
const SETTINGS = { name: 'relay-test', email: 'you@example.com', account: ACCOUNT, database: 'db-id', subdomain: 'you', team: 'you.cloudflareaccess.com',
  access: { id: 'app-id', aud: 'aud' } };

test('the install\'s configs carry its own names, IDs and owner, and no secret', () => {
  const { app, mcp, spaces } = configs(templates, SETTINGS);
  assert.equal(app.name, 'relay-test');
  assert.equal(app.d1_databases[0].database_name, 'relay-test-db');
  assert.deepEqual([app.queues.producers[0].queue, app.queues.consumers[0].queue], ['relay-test-webhooks', 'relay-test-webhooks']);
  assert.equal(app.services[0].service, 'relay-test-mcp');
  assert.equal(app.vars.CF_ACCESS_APP_ID, 'app-id');
  assert.equal(mcp.vars.RELAY_MCP_ADDRESS, 'https://relay-test-mcp.you.workers.dev/mcp');
  assert.equal(mcp.d1_databases[0].database_id, 'db-id');
  assert.equal(mcp.queues.producers[0].queue, 'relay-test-webhooks');
  assert.deepEqual([app.vars.RELAY_SIGN_IN, app.vars.RELAY_MCP_CALLBACK], ['access', 'https://relay-test-mcp.you.workers.dev/callback']);
  assert.equal(mcp.vars.RELAY_SERVER_URL, 'https://relay-test.you.workers.dev');
  assert.equal(mcp.vars.WONG_OWNER_EMAIL, undefined);
  assert.deepEqual([spaces.name, spaces.account_id, spaces.queues.producers[0].queue], ['relay-test-spaces', ACCOUNT, 'relay-test-webhooks']);
  for (const config of [app, mcp]) assert.equal(config.durable_objects.bindings[0].script_name, 'relay-test-spaces');
  assert.equal(app.triggers, undefined);
  assert.deepEqual(keysApp('Keys', 'h.example.com').destinations.map(item => item.uri), ['h.example.com/apps/relay/api']);
  assert.equal(bypassPolicy.decision, 'bypass');
  assert.deepEqual(accessApp(names('relay-test').app, 'relay-test.you.workers.dev').destinations, [{ type: 'public', uri: 'relay-test.you.workers.dev' }]);
  assert.deepEqual(accessApp(names('relay-test').app, 'relay-test.you.workers.dev', 'w1').destinations[0], { type: 'worker', worker_id: 'w1' });
});

/** An install as install leaves it, and the answers update reads. */
function installed() {
  const place = files();
  const { app } = configs(templates, { ...SETTINGS, name: 'relay', workerId: 'w1' });
  writeFileSync(place.config, JSON.stringify(app));
  const answers = { [`GET /accounts/${ACCOUNT}/workers/subdomain`]: { subdomain: 'you' },
    [`GET /accounts/${ACCOUNT}/access/apps`]: [{ id: 'sso', name: names('relay').mcpApp }],
    [`POST /accounts/${ACCOUNT}/access/apps`]: { id: 'keys' }, [`GET /accounts/${ACCOUNT}/access/apps/keys/policies`]: [],
    [`POST /accounts/${ACCOUNT}/access/apps/keys/policies`]: {}, [`DELETE /accounts/${ACCOUNT}/access/apps/sso`]: {} };
  return { place, answers };
}
test('update writes each config again, opens the keys\' way past the login, and puts it live in order', async () => {
  const { place, answers } = installed();
  const ran = [];
  const lines = [];
  const { request, calls } = fakeCloudflare(answers);
  const result = await setup({ args: ['update'], env: { CLOUDFLARE_API_TOKEN: TOKEN, CLOUDFLARE_ACCOUNT_ID: ACCOUNT }, request,
    wrangler: args => ran.push(args.join(' ')), build: () => ran.push('build'), log: line => lines.push(line), files: place });
  assert.equal(result, 'ok');
  assert.deepEqual(ran.map(line => line.replace(place.config.replace(/wrangler\.jsonc$/, ''), '')), ['d1 migrations apply relay-db --remote -c wrangler.jsonc',
    'deploy -c wrangler.spaces.jsonc', 'deploy -c wrangler.mcp.jsonc', 'build', ran.at(-1)]);
  assert.match(ran.at(-1), /^deploy -c /);
  const spaces = JSON.parse(readFileSync(place.spaces, 'utf8'));
  assert.equal(spaces.name, 'relay-spaces');
  assert.deepEqual(settingsOf(JSON.parse(readFileSync(place.config, 'utf8')), 'you'), { ...SETTINGS, name: 'relay', workerId: 'w1' });
  assert.ok(calls.includes(`POST /accounts/${ACCOUNT}/access/apps/keys/policies`), 'the keys app gets its bypass policy');
  assert.ok(calls.includes(`DELETE /accounts/${ACCOUNT}/access/apps/sso`), 'the old connector sign-in app goes');
  assert.ok(lines.includes('ok database changes applied, then the newest Relay Everything put live'));
});

test('a failed database change stops update before anything goes live', async () => {
  const { place, answers } = installed();
  const ran = [];
  const wrangler = args => {
    ran.push(args.slice(0, 2).join(' '));
    if (args[0] === 'd1') throw new Error('migration 0042 failed');
  };
  await assert.rejects(run(['update'], answers, { files: place, wrangler }), /migration 0042 failed/);
  assert.deepEqual(ran, ['d1 migrations']);
});

test('remove lists what it would delete and deletes nothing without --yes', async () => {
  const { result, output, calls } = await run(['remove'], {});
  assert.equal(result, 'refused');
  assert.match(output, /can't be undone[\s\S]*D1 database relay-db/);
  assert.ok(calls.every(call => !call.startsWith('DELETE')));
});
