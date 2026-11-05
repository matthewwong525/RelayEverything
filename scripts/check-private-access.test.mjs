// Run with: node --test scripts/check-private-access.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { checkCheckerKey, checkPolicies, RELAY_DEVICES } from './check-private-access.mjs';
import { accessConflicts } from './lib-access-config.mjs';

const token = id => ({ service_token: { token_id: id } });
const human = { id: 'h', decision: 'allow', name: 'People', include: [{ email: { email: 'owner@example.com' } }] };
const checker = { id: 'm', decision: 'non_identity', name: 'Checker', include: [token('t-checker')] };
const devices = { id: 'r', decision: 'non_identity', name: RELAY_DEVICES, include: [token('t-phone'), token('t-pebble')] };
const app = (...policies) => ({ policies: policies.map(({ id }) => ({ id })) });
const unreviewed = /missing or unreviewed/;
const narrow = /exact reachable emails and one separate service token/;

test('the human and the checker policies pass, with or without Relay devices', () => {
  checkPolicies([human, checker], app(human, checker));
  checkPolicies([human, checker, devices], app(human, checker, devices));
});

test('a policy the app does not hold, a second devices policy or a stray one is refused', () => {
  assert.throws(() => checkPolicies([human, checker, devices], app(human, checker)), unreviewed);
  assert.throws(() => checkPolicies([human, checker, devices, { ...devices, id: 'r2' }], app(human, checker, devices, { id: 'r2' })), unreviewed);
  assert.throws(() => checkPolicies([human, checker, { ...human, id: 'b', decision: 'bypass' }], app(human, checker, { id: 'b' })), unreviewed);
  assert.throws(() => checkPolicies([human, { ...devices, id: 'm' }], app(human, devices)), unreviewed);
});

test('Relay devices holds service tokens alone, at least one, and no exception', () => {
  for (const include of [[], [token('t'), { everyone: {} }], [{ ...token('t'), email: { email: 'a@b.co' } }], [{ service_token: {} }]]) {
    assert.throws(() => checkPolicies([human, checker, { ...devices, include }], app(human, checker, devices)), narrow, JSON.stringify(include));
  }
  assert.throws(() => checkPolicies([human, checker, { ...devices, require: [token('t')] }], app(human, checker, devices)), narrow);
});

test('the checker keeps exactly one service token, and the human policy exact emails', () => {
  assert.throws(() => checkPolicies([human, { ...checker, include: [token('a'), token('b')] }], app(human, checker)), narrow);
  assert.throws(() => checkPolicies([{ ...human, include: [{ email: { email: 'bot@users.noreply.github.com' } }] }, checker], app(human, checker)), narrow);
});

// The fingerprints of 'live.access' and 'preview.access'.
const config = { vars: { RELAY_CHECKER_SHA256: 'c7b5ca4ae66d39e8a45c98a6d84e28dec8a393b352acae80ee14ecfcf07c72b2' }, env: { staging: { vars: { RELAY_CHECKER_SHA256: '7f85e7ddfcde90b53f005891ad969fb9d5cc76bb19c63f2b72818b2ccb67fbc3' } } } };
const reads = clientId => { const asked = []; return { asked, read: async id => { asked.push(id); return { id, client_id: clientId, name: 'checker' }; } }; };

test("the checker policy's token must be the Client ID each environment's var names", async () => {
  const live = reads('live.access');
  assert.equal(await checkCheckerKey(config, 'production', [human, checker, devices], live.read), 'matches');
  assert.deepEqual(live.asked, ['t-checker']);
  assert.equal(await checkCheckerKey(config, 'staging', [human, checker], reads('preview.access').read), 'matches');
});

test('a new checker key that the var does not name fails, and names the var, the file and the new fingerprint', async () => {
  await assert.rejects(checkCheckerKey(config, 'staging', [human, checker], reads('new.access').read), error => {
    assert.match(error.message, /RELAY_CHECKER_SHA256/);
    assert.ok(!error.message.includes('new.access'));
    assert.match(error.message, /app\/wrangler\.jsonc \(env\.staging\.vars\)/);
    assert.match(error.message, /bccbf9ea7036b264b22b4565f8bb373d4b12ca711585f52abe7c160ae747a296/);
    return true;
  });
  await assert.rejects(checkCheckerKey(config, 'production', [human, checker], reads('preview.access').read), /app\/wrangler\.jsonc \(vars\)/);
  const missing = { ...config, env: { staging: { vars: {} } } };
  await assert.rejects(checkCheckerKey(missing, 'staging', [human, checker], reads('preview.access').read), /RELAY_CHECKER_SHA256 is missing for staging/);
});

test('the message never holds a secret, even when the read returns one', async () => {
  const read = async () => ({ client_id: 'new.access', client_secret: 'do-not-print' });
  await assert.rejects(checkCheckerKey(config, 'production', [human, checker], read), error => !error.message.includes('do-not-print'));
});

test('a key that may not read service tokens leaves it unverified; another failure still stops; no Relay skips it', async () => {
  const refused = async () => { throw Object.assign(new Error('Cloudflare read-only protection check failed (403)'), { status: 403 }); };
  assert.equal(await checkCheckerKey(config, 'production', [human, checker], refused), 'unverified');
  const down = async () => { throw Object.assign(new Error('Cloudflare read-only protection check failed (502)'), { status: 502 }); };
  await assert.rejects(checkCheckerKey(config, 'production', [human, checker], down), /502/);
  assert.equal(await checkCheckerKey({ vars: {} }, 'production', [human, checker], down), undefined);
});

test("Relay's AI connector sign-in, an Access for SaaS app, guards none of the app's addresses", () => {
  const workers = [{ id: 'w-live', name: 'relay-everything' }, { id: 'w-staging', name: 'relay-everything-staging' }];
  const saas = { id: 'saas', name: 'relay-everything AI connector', type: 'saas', policies: [{ id: 'owner' }],
    saas_app: { auth_type: 'oidc', redirect_uris: ['https://relay-everything-mcp.example.workers.dev/callback'] } };
  const withDomain = { ...saas, id: 'saas-2', domain: 'team.cloudflareaccess.com/cdn-cgi/access/sso/oidc/abc' };
  assert.deepEqual(accessConflicts([saas, withDomain], workers, 'example', []), []);
  // The same check still catches an app on the live Worker's own address.
  const stray = { id: 'stray', domain: 'relay-everything.example.workers.dev' };
  assert.deepEqual(accessConflicts([saas, stray], workers, 'example', []).map(app => app.id), ['stray']);
});
