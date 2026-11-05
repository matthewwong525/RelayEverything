// Run with: node --test scripts/relay-device-key.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { connectCode, handOverPage, listing, parseCommand, slug, withoutToken, withToken } from './relay-device-key.mjs';

test('a command needs a known verb, and a name to make or revoke a key', () => {
  assert.deepEqual(parseCommand(['create', '--name', ' Android phone ']), { command: 'create', name: 'Android phone', staging: false, server: undefined });
  assert.deepEqual(parseCommand(['list', '--staging']), { command: 'list', name: undefined, staging: true, server: undefined });
  assert.equal(parseCommand(['revoke', '--name', "Matt's iPhone", '--server', 'https://relay.example.com']).server, 'https://relay.example.com');
  for (const args of [[], ['delete'], ['create'], ['revoke', '--name', ''], ['create', '--name', 'x'.repeat(41)], ['create', '--name', '<b>'],
    ['create', '--name', 'Phone', '--server', 'http://relay.example.com'], ['create', '--name', 'Phone', '--server', 'https://relay.example.com/x']]) {
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
  const rows = [{ name: 'Phone', token_client_id: 'abc.access', created_at: Date.UTC(2026, 10, 5), revoked_at: null },
    { name: 'Old', token_client_id: 'old.access', created_at: Date.UTC(2026, 0, 1), revoked_at: Date.UTC(2026, 5, 1) }];
  assert.equal(listing(rows), 'Phone\tmade 2026-11-05\ton\tabc.access\nOld\tmade 2026-01-01\tturned off 2026-06-01\told.access');
  assert.match(listing([]), /No device keys yet/);
});

test('a page name is safe as a file name', () => {
  assert.equal(slug("Matt's iPhone 15"), 'matt-s-iphone-15');
  assert.equal(slug('—'), 'device');
});
