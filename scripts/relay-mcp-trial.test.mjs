// Run with: node --test scripts/relay-mcp-trial.test.mjs
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { cookieJar, parseArgs, pkce, trial } from './relay-mcp-trial.mjs';

const STAGING = 'https://relay-everything-mcp-staging.matthewwong525.workers.dev';
const SERVER = 'https://app-staging.relayeverything.com';

/** The staging connector as an AI app meets it, before anyone signs in. `open` lets /mcp in with no token. */
function fakeConnector({ open = false } = {}) {
  const seen = [];
  const request = async (url, init = {}) => {
    const { origin, pathname } = new URL(url);
    const key = `${init.method ?? 'GET'} ${origin === STAGING ? pathname : origin}`;
    seen.push({ key, headers: new Headers(init.headers) });
    switch (key) {
      case 'GET /.well-known/oauth-authorization-server': return Response.json({ registration_endpoint: `${STAGING}/register` });
      case 'GET /.well-known/oauth-protected-resource/mcp': return Response.json({ resource: `${STAGING}/mcp` });
      case 'POST /mcp': return new Response(null, { status: open ? 200 : 401 });
      case 'GET /v1/me': return new Response(null, { status: new Headers(init.headers).has('Authorization') ? 403 : 401 });
      case 'GET /v1/openapi.json': return Response.json({ openapi: '3.1.0' });
      case 'POST /register': return Response.json({ client_id: 'c1' }, { status: 201 });
      case 'GET /authorize': return new Response('<h1>Connect Relay Everything trial to Relay Everything?</h1><input name="handle" value="h1">',
        { headers: { 'Set-Cookie': '__Host-oauth-consent-x=abc; Path=/; Secure' } });
      case 'POST /authorize': return new Response(null, { status: 302,
        headers: { Location: `${SERVER}/apps/relay/sign-in/connect?state=s1` } });
      case `GET ${SERVER}`: return new Response('<h1>Sign in to Relay Everything</h1>');
      case 'GET /callback': return new Response('refused', { status: 400 });
      case 'POST /token': return Response.json({ error: 'invalid_grant' }, { status: 400 });
      default: throw new Error(`unexpected ${key}`);
    }
  };
  return { request, seen };
}

const run = async (connector, options = {}) => {
  const printed = [];
  const passed = await trial({ live: false, signIn: false, env: { CF_ACCESS_STAGING_CLIENT_ID: 'checker.access', CF_ACCESS_STAGING_CLIENT_SECRET: 'checker-secret' },
    request: connector.request, log: line => printed.push(line), ...options });
  return { passed, printed };
};

test('the flags pick the live check or a sign-in, never both', () => {
  assert.deepEqual(parseArgs([]), { live: false, signIn: false });
  assert.deepEqual(parseArgs(['--sign-in']), { live: false, signIn: true });
  assert.deepEqual(parseArgs(['--live']), { live: true, signIn: false });
});

test('a PKCE challenge is the verifier hashed, and the jar sends back the cookies it kept', () => {
  const { verifier, challenge } = pkce();
  assert.equal(challenge, createHash('sha256').update(verifier).digest('base64url'));
  const jar = cookieJar();
  jar.keep(new Response(null, { headers: [['Set-Cookie', 'a=1; Path=/'], ['Set-Cookie', 'b=2']] }));
  jar.keep(new Response(null, { headers: { 'Set-Cookie': 'a=; Max-Age=0' } }));
  assert.equal(jar.header(), 'b=2');
});

test('the staging trial passes a connector that refuses every stranger, and keeps the consent cookie', async () => {
  const connector = fakeConnector();
  const { passed, printed } = await run(connector);
  assert.equal(passed, true, printed.join('\n'));
  assert.ok(printed.includes('ok refuses a service token'));
  assert.ok(printed.includes('ok refuses an unknown key on the web API'));
  assert.ok(printed.includes('ok describes the web API with no sign-in'));
  assert.ok(printed.includes("ok sends an approved app on to the server's sign-in"));
  assert.ok(printed.includes('ok the server sends no code to someone not signed in'));
  const approve = connector.seen.find(call => call.key === 'POST /authorize');
  assert.equal(approve.headers.get('Cookie'), '__Host-oauth-consent-x=abc');
  assert.ok(!printed.join('\n').includes('checker-secret'));
});

test('the trial fails a connector that lets /mcp in with no token; the live one checks only that and its metadata', async () => {
  const { passed, printed } = await run(fakeConnector({ open: true }));
  assert.equal(passed, false);
  assert.ok(printed.includes('failed refuses /mcp with no token: 200'));
  const live = await run({ request: async url => ['/mcp', '/v1/me'].includes(new URL(url).pathname) ? new Response(null, { status: 401 })
    : Response.json({ registration_endpoint: 'https://relay-everything-mcp.matthewwong525.workers.dev/register' }) }, { live: true });
  assert.deepEqual(live, { passed: true, printed: ['Trying relay-everything-mcp at https://relay-everything-mcp.matthewwong525.workers.dev',
    'ok answers its OAuth metadata', 'ok refuses /mcp with no token', 'ok refuses the web API with no token'] });
});
