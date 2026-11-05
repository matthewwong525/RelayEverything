// Run with: node --test scripts/relay-mcp-setup.test.mjs
import assert from 'node:assert/strict';
import { join } from 'node:path';
import test from 'node:test';
import { parseConfig, repoRoot } from './lib-wrangler-config.mjs';
import { missingSecrets, NEEDED, ownerPolicy, parseArgs, permissionLines, reportLine, saasApp, setup, signInValues, target } from './relay-mcp-setup.mjs';

const config = parseConfig(join(repoRoot, 'app', 'wrangler.relay-mcp.jsonc'));

test('the flags pick the environment and a check-only run', () => {
  assert.deepEqual(parseArgs([]), { staging: false, check: false });
  assert.deepEqual(parseArgs(['--staging', '--check']), { staging: true, check: true });
});

test('the check names each missing permission and passes a token that holds all four', () => {
  assert.deepEqual(permissionLines(Object.values(NEEDED)), ['ok Access apps', 'ok Access team domain', 'ok KV', 'ok Workers scripts']);
  assert.deepEqual(permissionLines(['Workers Scripts Write']), ['missing Access apps: add "Access: Apps and Policies Write" to the token',
    'missing Access team domain: add "Access: Organizations, Identity Providers, and Groups Read" to the token',
    'missing KV: add "Workers KV Storage Write" to the token', 'ok Workers scripts']);
  // A Write group covers its Read.
  assert.equal(permissionLines(['Access: Organizations, Identity Providers, and Groups Write'])[1], 'ok Access team domain');
});

test('each environment gets its own Worker, sign-in app and callback, for the owner alone', () => {
  const live = target(config, false);
  const staging = target(config, true);
  assert.deepEqual([live.worker, live.app, live.callback], ['relay-ring-mcp', 'relay-ring AI connector', 'https://relay-ring-mcp.matthewwong525.workers.dev/callback']);
  assert.deepEqual([staging.worker, staging.app, staging.callback],
    ['relay-ring-mcp-staging', 'relay-ring AI connector (staging)', 'https://relay-ring-mcp-staging.matthewwong525.workers.dev/callback']);
  assert.equal(staging.owner, 'matthewwong525@gmail.com');
  assert.deepEqual(saasApp(staging).saas_app.redirect_uris, [staging.callback]);
  assert.equal(saasApp(staging).type, 'saas');
  assert.deepEqual(ownerPolicy(staging.owner).include, [{ email: { email: 'matthewwong525@gmail.com' } }]);
});

test('the sign-in values come from the team domain and the client', () => {
  const values = signInValues('team.cloudflareaccess.com', { client_id: 'abc123', client_secret: 'shh-client-secret' });
  assert.equal(values.ACCESS_TOKEN_URL, 'https://team.cloudflareaccess.com/cdn-cgi/access/sso/oidc/abc123/token');
  assert.deepEqual(missingSecrets(['ACCESS_CLIENT_ID', 'OTHER']), Object.keys(values).filter(name => name !== 'ACCESS_CLIENT_ID'));
  assert.deepEqual(missingSecrets(Object.keys(values)), []);
  assert.equal(reportLine('worker relay-ring-mcp', ''), 'ok worker relay-ring-mcp');
});

const ACCOUNT = '0123456789abcdef0123456789abcdef';
const SECRET = 'shh-client-secret-from-cloudflare';
const CLIENT = '8f3e1c2b7a6d5e4f3c2b1a0f9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a2f1e0d';

/** Cloudflare's API as setup uses it, for an account with nothing set up yet. It keeps what setup makes. */
function fakeCloudflare() {
  const state = { workers: new Set(), apps: [], policies: new Map(), secrets: new Set() };
  const answers = {
    'GET /user/tokens/verify': () => ({ id: 'token-1' }),
    'GET /user/tokens/token-1': () => ({ policies: [{ effect: 'allow', permission_groups: Object.values(NEEDED).map(name => ({ name })) }] }),
    'GET /workers/scripts/:worker/settings': worker => state.workers.has(worker) ? {} : null,
    'GET /access/apps': () => state.apps,
    'POST /access/apps': (_, body) => {
      const app = { ...body, id: 'app-1', saas_app: { ...body.saas_app, client_id: CLIENT, client_secret: SECRET } };
      state.apps.push({ ...app, saas_app: { ...app.saas_app, client_secret: undefined } });
      return app;
    },
    'GET /access/apps/:app/policies': app => state.policies.get(app) ?? [],
    'POST /access/apps/:app/policies': (app, body) => { state.policies.set(app, [body]); return body; },
    'GET /workers/scripts/:worker/secrets': () => [...state.secrets].map(name => ({ name, type: 'secret_text' })),
    'GET /access/organizations': () => ({ auth_domain: 'team.cloudflareaccess.com' }),
  };
  const request = async (url, { method, body }) => {
    const path = new URL(url).pathname.replace('/client/v4', '').replace(`/accounts/${ACCOUNT}`, '');
    const [, kind, name, rest] = /^\/(workers\/scripts|access\/apps)\/([^/]+)(\/.+)$/.exec(path) ?? [];
    const key = `${method} ${kind ? `/${kind}/:${kind === 'access/apps' ? 'app' : 'worker'}${rest}` : path}`;
    const result = answers[key]?.(name ?? null, body && JSON.parse(body));
    if (result === undefined) throw new Error(`unexpected ${key}`);
    return result === null ? Response.json({ success: false, errors: [] }, { status: 404 }) : Response.json({ success: true, result });
  };
  const wrangler = (args, input) => {
    calls.push({ args, input });
    if (args[0] === 'deploy') state.workers.add(args.includes('staging') ? 'relay-ring-mcp-staging' : 'relay-ring-mcp');
    if (args[0] === 'secret') for (const name of Object.keys(JSON.parse(input))) state.secrets.add(name);
  };
  const calls = [];
  return { request, wrangler, calls, state };
}

test('a setup run puts the secrets through wrangler and prints none; a second run changes nothing', async () => {
  const cloudflare = fakeCloudflare();
  const run = async () => {
    const printed = [];
    await setup({ args: ['--staging'], env: { CLOUDFLARE_API_TOKEN: 'cf-user-token-value', CLOUDFLARE_ACCOUNT_ID: ACCOUNT },
      request: cloudflare.request, wrangler: cloudflare.wrangler, log: line => printed.push(line) });
    return printed.join('\n');
  };
  const first = await run();
  assert.deepEqual(cloudflare.calls.map(call => call.args), [['deploy', '--env', 'staging'], ['secret', 'bulk', '--env', 'staging']]);
  const sent = JSON.parse(cloudflare.calls[1].input);
  assert.equal(sent.ACCESS_CLIENT_SECRET, SECRET);
  assert.match(first, /ok worker relay-ring-mcp-staging \(deployed\)/);
  assert.match(first, /ok sign-in secrets \(put ACCESS_CLIENT_ID, ACCESS_CLIENT_SECRET, /);
  assert.deepEqual(cloudflare.state.policies.get('app-1')[0].include, [{ email: { email: 'matthewwong525@gmail.com' } }]);
  for (const value of [...Object.values(sent), 'cf-user-token-value']) assert.ok(!first.includes(value), `the output shows ${value}`);

  const second = await run();
  assert.equal(cloudflare.calls.length, 2);
  assert.match(second, /^ok worker relay-ring-mcp-staging$/m);
  assert.match(second, /^ok sign-in secrets$/m);
});
