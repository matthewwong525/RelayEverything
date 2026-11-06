// Run with: node --test scripts/relay-forward/worker.test.mjs
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { after, before, test } from 'node:test';
import { join } from 'node:path';
import { miniflare } from '../lib-miniflare.mjs';
import { repoRoot } from '../lib-wrangler-config.mjs';

const TARGET = 'https://app.example.com';
const seen = [];
let forward;
let hold;

const start = (create, MODE) => create({
  modules: true, scriptPath: join(repoRoot, 'scripts', 'relay-forward', 'worker.mjs'), compatibilityDate: '2026-07-28',
  bindings: { MODE, TARGET },
  outboundService: async request => {
    seen.push({ method: request.method, url: request.url, headers: Object.fromEntries(request.headers), body: Buffer.from(await request.arrayBuffer()) });
    return new Response('kept', { status: 201 });
  },
});

before(async () => {
  const create = await miniflare();
  [forward, hold] = [start(create, 'forward'), start(create, 'hold')];
});
after(() => Promise.all([forward?.dispose(), hold?.dispose()]));

const send = { method: 'POST', headers: {
  'Content-Type': 'application/octet-stream', 'CF-Access-Client-Id': 'phone.access', 'CF-Access-Client-Secret': 'phone-secret',
  'Cf-Access-Jwt-Assertion': 'old-app-pass', Cookie: 'CF_Authorization=old-app-pass', 'X-Pebble-Signature': 'sig' } };

test('a send reaches the new address byte for byte, with the device key and without the old app\'s sign-in', async () => {
  seen.length = 0;
  const body = randomBytes(4096);
  const answer = await forward.dispatchFetch('https://relay-ring.example.workers.dev/apps/relay/api/pebble?x=1', { ...send, body });
  assert.equal(answer.status, 201);
  assert.equal(await answer.text(), 'kept');
  assert.equal(seen.length, 1);
  const [request] = seen;
  assert.equal(request.method, 'POST');
  assert.equal(request.url, `${TARGET}/apps/relay/api/pebble?x=1`);
  assert.ok(request.body.equals(body));
  assert.equal(request.headers['cf-access-client-id'], 'phone.access');
  assert.equal(request.headers['cf-access-client-secret'], 'phone-secret');
  assert.equal(request.headers['x-pebble-signature'], 'sig');
  assert.equal(request.headers['cf-access-jwt-assertion'], undefined);
  assert.equal(request.headers.cookie, undefined);
});

test('a phone\'s read is passed on, not redirected', async () => {
  seen.length = 0;
  const answer = await forward.dispatchFetch('https://relay-ring.example.workers.dev/apps/relay/api/notes', { headers: { Accept: 'application/json' } });
  assert.equal(answer.status, 201);
  assert.deepEqual(seen.map(request => [request.method, request.url]), [['GET', `${TARGET}/apps/relay/api/notes`]]);
});

test('a browser page load goes to the same page and query at the new address', async () => {
  seen.length = 0;
  const answer = await forward.dispatchFetch('https://relay-ring.example.workers.dev/apps/relay/?day=2026-11-05',
    { headers: { Accept: 'text/html,application/xhtml+xml' }, redirect: 'manual' });
  assert.equal(answer.status, 308);
  assert.equal(answer.headers.get('location'), `${TARGET}/apps/relay/?day=2026-11-05`);
  assert.equal(seen.length, 0);
});

test('hold answers 503 with try again in a minute, to a send and a page alike', async () => {
  seen.length = 0;
  for (const init of [{ ...send, body: 'note' }, { headers: { Accept: 'text/html' }, redirect: 'manual' }]) {
    const answer = await hold.dispatchFetch('https://relay-ring.example.workers.dev/apps/relay/api/pebble', init);
    assert.equal(answer.status, 503);
    assert.equal(answer.headers.get('retry-after'), '60');
    assert.match(await answer.text(), /Relay Everything is moving; try again in a minute/);
  }
  assert.equal(seen.length, 0);
});
