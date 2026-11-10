// Run with: node --test app/self-host/*.test.mjs
// An install carries every part of Relay's server: a binding Relay adds to app/ and not here fails, by name.
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { parseConfig, repoRoot } from '../../scripts/lib-wrangler-config.mjs';

const app = parseConfig(join(repoRoot, 'app', 'wrangler.jsonc'));
const install = parseConfig(join(repoRoot, 'app', 'self-host', 'wrangler.template.jsonc'));
const connector = parseConfig(join(repoRoot, 'app', 'wrangler.relay-mcp.jsonc'));
const installConnector = parseConfig(join(repoRoot, 'app', 'self-host', 'mcp.template.jsonc'));
const spaces = parseConfig(join(repoRoot, 'app', 'wrangler.spaces.jsonc'));
const installSpaces = parseConfig(join(repoRoot, 'app', 'self-host', 'spaces.template.jsonc'));
// WongStack's own parts, which an install leaves out: the memory store, the live line, the code store and the app's
// schedule. Relay Everything has no schedule: each space's alarm wakes its own webhooks.
const WONGSTACK = /^(MEMORY_|LIVE_LINE$|ARTIFACTS$|cron )/;

/** Every binding a config names, as `kind BINDING`. */
const bindings = config => [
  ...(config.d1_databases ?? []).map(item => `d1 ${item.binding}`), ...(config.r2_buckets ?? []).map(item => `r2 ${item.binding}`),
  ...(config.queues?.producers ?? []).map(item => `queue ${item.binding}`), ...(config.queues?.consumers ?? []).map(() => 'queue consumer'),
  ...(config.services ?? []).map(item => `service ${item.binding}`), ...(config.kv_namespaces ?? []).map(item => `kv ${item.binding}`),
  ...(config.durable_objects?.bindings ?? []).map(item => `durable object ${item.name}`), ...(config.artifacts ?? []).map(item => `artifacts ${item.binding}`),
  ...(config.triggers?.crons ?? []).map(cron => `cron ${cron}`), ...(config.assets ? ['assets'] : []),
];
const wongstack = binding => WONGSTACK.test(binding) || WONGSTACK.test(binding.split(' ').at(-1));
// The knowledge web needs Workers Paid, so an install leaves it out and its server says the web is not set up.
const PAID_ONLY = ['artifacts KNOWLEDGE'];
const relayOnly = config => bindings(config).filter(binding => !wongstack(binding));

test('the install has every Relay binding of the full app', () => {
  assert.deepEqual(relayOnly(app).filter(binding => !bindings(install).includes(binding)), []);
  assert.equal(install.compatibility_date, app.compatibility_date);
  assert.deepEqual(install.compatibility_flags, app.compatibility_flags);
});

test('the install has no WongStack binding, and its connector matches Relay\'s', () => {
  assert.deepEqual(bindings(install).filter(wongstack), []);
  assert.deepEqual(bindings(installConnector), bindings(connector).filter(binding => !PAID_ONLY.includes(binding)));
  assert.equal(installConnector.compatibility_date, connector.compatibility_date);
});

test('the server and the connector reach the install\'s own spaces Worker, as the full app reaches its own', () => {
  const spacesOf = config => config.durable_objects?.bindings?.find(item => item.name === 'SPACES');
  for (const config of [app, connector]) assert.deepEqual(spacesOf(config), { name: 'SPACES', class_name: 'Space', script_name: spaces.name });
  for (const config of [install, installConnector]) assert.deepEqual(spacesOf(config), { name: 'SPACES', class_name: 'Space', script_name: installSpaces.name });
  for (const part of ['main', 'compatibility_date', 'compatibility_flags', 'rules', 'durable_objects', 'migrations']) {
    assert.deepEqual(installSpaces[part], part === 'main' ? '../worker/spaces-worker.ts' : spaces[part], part);
  }
  assert.deepEqual(bindings(installSpaces), bindings(spaces));
});

test('no Relay migration reads a WongStack table', () => {
  const folder = join(repoRoot, 'schema', 'migrations');
  const relay = readdirSync(folder).filter(file => file.includes('relay')).map(file => readFileSync(join(folder, file), 'utf8').replace(/--.*$/gm, ''));
  assert.ok(relay.length > 0);
  for (const sql of relay) assert.doesNotMatch(sql, /\b(FROM|JOIN|REFERENCES)\s+(?!relay_)\w+/i);
});
