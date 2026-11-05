// Run with: node --test self-host/
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { accessApp, configs, names, PARTS, parseCommand, setup } from './setup.mjs';

const TOKEN = 'test-token-never-printed-0123456789';
const ACCOUNT = 'a'.repeat(32);
const template = file => readFileSync(join(import.meta.dirname, file), 'utf8');
const files = () => {
  const dir = mkdtempSync(join(tmpdir(), 'relay-self-host-'));
  return { config: join(dir, 'wrangler.jsonc'), mcp: join(dir, 'wrangler.mcp.jsonc') };
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

test('the install\'s configs carry its own names, IDs and owner, and no secret', () => {
  const { app, mcp } = configs(template('wrangler.template.jsonc'), template('mcp.template.jsonc'), { name: 'relay-test', email: 'you@example.com',
    account: ACCOUNT, database: 'db-id', subdomain: 'you', team: 'you.cloudflareaccess.com', access: { id: 'app-id', aud: 'aud' } });
  assert.equal(app.name, 'relay-test');
  assert.equal(app.d1_databases[0].database_name, 'relay-test-db');
  assert.deepEqual([app.queues.producers[0].queue, app.queues.consumers[0].queue], ['relay-test-webhooks', 'relay-test-webhooks']);
  assert.equal(app.services[0].service, 'relay-test-mcp');
  assert.equal(app.vars.CF_ACCESS_APP_ID, 'app-id');
  assert.equal(mcp.vars.RELAY_MCP_ADDRESS, 'https://relay-test-mcp.you.workers.dev/mcp');
  assert.equal(mcp.d1_databases[0].database_id, 'db-id');
  assert.deepEqual(accessApp(names('relay-test').app, 'relay-test.you.workers.dev').destinations, [{ type: 'public', uri: 'relay-test.you.workers.dev' }]);
});

test('a failed database change stops update before anything goes live', async () => {
  const place = files();
  writeFileSync(place.config, JSON.stringify({ name: 'relay', d1_databases: [{ database_name: 'relay-db' }] }));
  const ran = [];
  const wrangler = args => {
    ran.push(args.slice(0, 2).join(' '));
    if (args[0] === 'd1') throw new Error('migration 0042 failed');
  };
  await assert.rejects(run(['update'], {}, { files: place, wrangler }), /migration 0042 failed/);
  assert.deepEqual(ran, ['d1 migrations']);
});

test('remove lists what it would delete and deletes nothing without --yes', async () => {
  const { result, output, calls } = await run(['remove'], {});
  assert.equal(result, 'refused');
  assert.match(output, /can't be undone[\s\S]*D1 database relay-db/);
  assert.ok(calls.every(call => !call.startsWith('DELETE')));
});
