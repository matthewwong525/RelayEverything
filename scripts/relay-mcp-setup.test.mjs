// Run with: node --test scripts/relay-mcp-setup.test.mjs
import assert from 'node:assert/strict';
import { join } from 'node:path';
import test from 'node:test';
import { parseConfig, repoRoot } from './lib-wrangler-config.mjs';
import { googleLine, NEEDED, parseArgs, permissionLines, reportLine, setup, target } from './relay-mcp-setup.mjs';

const config = parseConfig(join(repoRoot, 'app', 'wrangler.relay-mcp.jsonc'));

test('the flags pick the environment and a check-only run', () => {
  assert.deepEqual(parseArgs([]), { staging: false, check: false });
  assert.deepEqual(parseArgs(['--staging', '--check']), { staging: true, check: true });
});

test('the check names each missing permission and passes a token that holds both', () => {
  assert.deepEqual(permissionLines(Object.values(NEEDED)), ['ok KV', 'ok Workers scripts']);
  assert.deepEqual(permissionLines(['Workers Scripts Write']), ['missing KV: add "Workers KV Storage Write" to the token', 'ok Workers scripts']);
});

test('each environment gets its own Worker, callback and sign-in server', () => {
  const live = target(config, false);
  const staging = target(config, true);
  assert.deepEqual(live, { worker: 'relay-everything-mcp', address: 'https://relay-everything-mcp.matthewwong525.workers.dev/mcp',
    callback: 'https://relay-everything-mcp.matthewwong525.workers.dev/callback', server: 'https://app.relayeverything.com' });
  assert.deepEqual([staging.worker, staging.callback, staging.server], ['relay-everything-mcp-staging',
    'https://relay-everything-mcp-staging.matthewwong525.workers.dev/callback', 'https://app-staging.relayeverything.com']);
  assert.equal(reportLine('worker relay-everything-mcp', ''), 'ok worker relay-everything-mcp');
});

const ACCOUNT = '0123456789abcdef0123456789abcdef';

/** Cloudflare's API as setup uses it, for an account with nothing set up yet. It keeps what setup makes. */
function fakeCloudflare() {
  const state = { workers: new Set() };
  const answers = {
    'GET /user/tokens/verify': () => ({ id: 'token-1' }),
    'GET /user/tokens/token-1': () => ({ policies: [{ effect: 'allow', permission_groups: Object.values(NEEDED).map(name => ({ name })) }] }),
    'GET /workers/scripts/:worker/settings': worker => state.workers.has(worker) ? {} : null,
  };
  const request = async (url, { method }) => {
    const path = new URL(url).pathname.replace('/client/v4', '').replace(`/accounts/${ACCOUNT}`, '');
    const [, name, rest] = /^\/workers\/scripts\/([^/]+)(\/.+)$/.exec(path) ?? [];
    const key = `${method} ${name ? `/workers/scripts/:worker${rest}` : path}`;
    const result = answers[key]?.(name ?? null);
    if (result === undefined) throw new Error(`unexpected ${key}`);
    return result === null ? Response.json({ success: false, errors: [] }, { status: 404 }) : Response.json({ success: true, result });
  };
  const wrangler = (args, input) => {
    calls.push(input === undefined ? args : [...args, `<stdin ${input.length}>`]);
    if (args[0] === 'deploy') state.workers.add(args.includes('staging') ? 'relay-everything-mcp-staging' : 'relay-everything-mcp');
  };
  const calls = [];
  return { request, wrangler, calls, state };
}

test('a setup run deploys the Worker once and prints no token; a second run changes nothing; a Google secret is put from .env', async () => {
  const cloudflare = fakeCloudflare();
  const run = async (args = ['--staging'], more = {}) => {
    const printed = [];
    await setup({ args, env: { CLOUDFLARE_API_TOKEN: 'cf-user-token-value', CLOUDFLARE_ACCOUNT_ID: ACCOUNT, ...more },
      request: cloudflare.request, wrangler: cloudflare.wrangler, log: line => printed.push(line) });
    return printed.join('\n');
  };
  const first = await run();
  assert.deepEqual(cloudflare.calls, [['deploy', '--env', 'staging']]);
  assert.match(first, /ok worker relay-everything-mcp-staging \(deployed\)/);
  assert.match(first, /^Sign-in: https:\/\/app-staging\.relayeverything\.com, back to https:\/\/relay-everything-mcp-staging\.matthewwong525\.workers\.dev\/callback$/m);
  assert.ok(!first.includes('cf-user-token-value'));

  const second = await run();
  assert.equal(cloudflare.calls.length, 1);
  assert.match(second, /^ok worker relay-everything-mcp-staging$/m);
  assert.match(await run(['--check']), /^skip Google: add RELAY_GOOGLE_SIGN_IN_SECRET to \.env/m);
  assert.equal(cloudflare.calls.length, 1);

  const google = { RELAY_GOOGLE_SIGN_IN_SECRET: 'google-secret-value' };
  assert.match(await run(['--staging', '--check'], google), /^ok Google secret RELAY_GOOGLE_SIGN_IN_SECRET$/m);
  assert.equal(cloudflare.calls.length, 1);
  const third = await run(['--staging'], google);
  assert.deepEqual(cloudflare.calls.at(-1), ['secret', 'put', 'RELAY_GOOGLE_SIGN_IN_SECRET', '--env', 'staging', '<stdin 19>']);
  assert.match(third, /^ok secret RELAY_GOOGLE_SIGN_IN_SECRET \(put\)$/m);
  assert.ok(!third.includes('google-secret-value'));
  assert.equal(googleLine({}), 'skip Google: add RELAY_GOOGLE_SIGN_IN_SECRET to .env to let the connector reach a person\'s Google');
});
