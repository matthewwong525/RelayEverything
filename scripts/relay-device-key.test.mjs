// Run with: node --test scripts/relay-device-key.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { join } from 'node:path';
import { parseConfig, repoRoot } from './lib-wrangler-config.mjs';
import { chatHandOverPage, configPath, connectCode, defaultServer, INSTALL, handOverPage, HAND_OVER, listing, parseCommand, slug, withoutToken, withToken } from './relay-device-key.mjs';

test('a command needs a known verb, and a name to make or revoke a key', () => {
  assert.deepEqual(parseCommand(['create', '--name', ' Android phone ']), { command: 'create', name: 'Android phone', staging: false, server: undefined, kind: 'phone' });
  assert.deepEqual(parseCommand(['list', '--staging']), { command: 'list', name: undefined, staging: true, server: undefined, kind: 'phone' });
  assert.equal(parseCommand(['create', '--name', 'Laptop', '--for', 'claude-code']).kind, 'claude-code');
  assert.equal(parseCommand(['revoke', '--name', "Matt's iPhone", '--server', 'https://relay.example.com']).server, 'https://relay.example.com');
  for (const args of [[], ['delete'], ['create'], ['revoke', '--name', ''], ['create', '--name', 'x'.repeat(41)], ['create', '--name', '<b>'],
    ['create', '--name', 'Phone', '--server', 'http://relay.example.com'], ['create', '--name', 'Laptop', '--for', 'chatgpt'], ['create', '--name', 'Phone', '--server', 'https://relay.example.com/x']]) {
    assert.ok(parseCommand(args).problem, JSON.stringify(args));
  }
});

test('a token joins or leaves the policy once, and other rules stay', () => {
  const other = { service_token: { token_id: 'other' } };
  assert.deepEqual(withToken([other], 'new'), [other, { service_token: { token_id: 'new' } }]);
  assert.deepEqual(withToken([other, { service_token: { token_id: 'new' } }], 'new'), [other, { service_token: { token_id: 'new' } }]);
  assert.deepEqual(withoutToken([other, { service_token: { token_id: 'gone' } }], 'gone'), [other]);
  assert.deepEqual(withoutToken([{ service_token: { token_id: 'gone' } }], 'gone'), []);
});

test('the connect code and the private page carry the key; the list never does', () => {
  const key = { server: 'https://relay.example.com', clientId: 'abc.access', clientSecret: 'shh-secret' };
  assert.deepEqual(JSON.parse(connectCode(key)), { relay: 1, ...key });
  const page = handOverPage({ ...key, name: '<Phone>', qrSvg: '<svg></svg>' });
  for (const part of ['&#60;Phone&#62;', 'shh-secret', 'abc.access', 'https://relay.example.com/apps/relay/api/pebble', '<svg></svg>',
    'Open the Relay app and tap Scan the QR code']) assert.ok(page.includes(part), part);
  assert.ok(handOverPage({ ...key, name: 'Phone', qrSvg: null }).includes('No QR code'));
  const rows = [{ name: 'Phone', reaches: 'phone', token_client_id: 'abc.access', created_at: Date.UTC(2026, 10, 5), revoked_at: null },
    { name: 'Old', reaches: 'phone', token_client_id: 'old.access', created_at: Date.UTC(2026, 0, 1), revoked_at: Date.UTC(2026, 5, 1) },
    { name: 'Laptop', reaches: 'chats', token_client_id: 'lap.access', created_at: Date.UTC(2026, 10, 5), revoked_at: null }];
  assert.equal(listing(rows), 'Phone\tphone\tmade 2026-11-05\ton\tabc.access\nOld\tphone\tmade 2026-01-01\tturned off 2026-06-01\told.access\n' +
    'Laptop\tclaude-code\tmade 2026-11-05\ton\tlap.access');
  assert.match(listing([]), /No device keys yet/);
});

test('a Claude Code key\'s page holds its connect code as text, escaped, with no QR code', () => {
  const code = connectCode({ server: 'https://relay.example.com', clientId: 'abc.access', clientSecret: 'shh-secret' });
  const page = chatHandOverPage({ name: 'Laptop', code });
  for (const part of ['Relay chat key: Laptop', '&#34;clientSecret&#34;:&#34;shh-secret&#34;', 'paste this connect code']) assert.ok(page.includes(part), part);
  assert.ok(!page.includes('<svg'));
});

test('a page name is safe as a file name', () => {
  assert.equal(slug("Matt's iPhone 15"), 'matt-s-iphone-15');
  assert.equal(slug('—'), 'device');
});

test('a new live key carries the site\'s own domain; a preview key keeps its workers.dev address', () => {
  const config = parseConfig(join(repoRoot, 'app', 'wrangler.jsonc'));
  const server = defaultServer(config, false);
  assert.equal(server, 'https://app.relayeverything.com');
  assert.equal(defaultServer(config, true), null);
  assert.equal(defaultServer({ routes: [{ pattern: 'a.example.com', custom_domain: true }], env: { staging: {} } }, true), 'https://a.example.com');
  assert.equal(defaultServer({}, false), null);
  const key = { server, clientId: 'abc.access', clientSecret: 'shh-secret' };
  assert.equal(JSON.parse(connectCode(key)).server, 'https://app.relayeverything.com');
  assert.ok(handOverPage({ ...key, name: 'Phone', qrSvg: null }).includes('https://app.relayeverything.com/apps/relay/api/pebble'));
  assert.match(HAND_OVER, /[\\/]\.relay-everything[\\/]device-keys$/);
});

test('on a person\'s own Relay server, keys use its config, and there are no previews', () => {
  assert.equal(configPath(false, true), INSTALL);
  assert.throws(() => configPath(true, true), /no previews/);
  assert.equal(configPath(false, false), join(repoRoot, 'app', 'wrangler.jsonc'));
  assert.equal(defaultServer(parseConfig(join(repoRoot, 'self-host', 'wrangler.template.jsonc')), false), null);
});
