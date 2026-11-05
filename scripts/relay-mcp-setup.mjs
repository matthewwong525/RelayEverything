#!/usr/bin/env node
// Relay's AI connector setup: its Worker and sign-in store, the Access for SaaS sign-in that admits only the owner,
// and the sign-in's values as Worker secrets. Each step is skipped when done. wiki/stack/relay-ai-connector.md
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { isMain, parseCli, usageError } from './lib-cli.mjs';
import { parseConfig, repoRoot, workerName } from './lib-wrangler-config.mjs';

const USAGE = `usage: node scripts/relay-mcp-setup.mjs [--staging] [--check]
  --staging   the previews' connector, relay-everything-mcp-staging, not the live one
  --check     only check that the Cloudflare token can do each step; change nothing`;

const APP = join(repoRoot, 'app');
const CONFIG = 'wrangler.relay-mcp.jsonc';
const SECRETS = ['ACCESS_CLIENT_ID', 'ACCESS_CLIENT_SECRET', 'ACCESS_AUTHORIZATION_URL', 'ACCESS_TOKEN_URL', 'ACCESS_JWKS_URL'];

/** The Cloudflare permission each step needs, by the name the token's policy lists. A Write group also covers its Read. */
export const NEEDED = { 'Access apps': 'Access: Apps and Policies Write', 'Access team domain': 'Access: Organizations, Identity Providers, and Groups Read',
  KV: 'Workers KV Storage Write', 'Workers scripts': 'Workers Scripts Write' };
const covers = (granted, group) => granted.includes(group) || granted.includes(group.replace(/ Read$/, ' Write'));

export function parseArgs(args) {
  const { values } = parseCli({ usage: USAGE, args, options: { staging: { type: 'boolean' }, check: { type: 'boolean' } } });
  return { staging: !!values.staging, check: !!values.check };
}

/** One line per step: `ok`, or the permission to add. */
export const permissionLines = granted => Object.entries(NEEDED)
  .map(([step, group]) => covers(granted, group) ? `ok ${step}` : `missing ${step}: add "${group}" to the token`);

/** The connector's name, address and owner for one environment, from its committed config. */
export function target(config, staging) {
  const vars = (staging ? config.env?.staging : config)?.vars ?? {};
  const address = new URL(vars.RELAY_MCP_ADDRESS);
  return { worker: workerName(config, staging ? 'staging' : undefined), address: address.href, callback: new URL('/callback', address).href,
    owner: vars.WONG_OWNER_EMAIL, app: `relay-everything AI connector${staging ? ' (staging)' : ''}` };
}

/** The Access for SaaS app: an OIDC sign-in that sends the owner back to the connector's /callback. */
export const saasApp = ({ app, callback }) => ({ name: app, type: 'saas', session_duration: '24h',
  saas_app: { auth_type: 'oidc', redirect_uris: [callback], grant_types: ['authorization_code'], scopes: ['openid', 'email', 'profile'] } });

/** Its one policy: the owner's email and no one else. */
export const ownerPolicy = owner => ({ name: 'Relay owner', decision: 'allow', include: [{ email: { email: owner } }], precedence: 1 });

/** The sign-in's values the connector reads, from Access's team domain and the app's client. */
export function signInValues(teamDomain, client) {
  const base = `https://${teamDomain}/cdn-cgi/access/sso/oidc/${client.client_id}`;
  return { ACCESS_CLIENT_ID: client.client_id, ACCESS_CLIENT_SECRET: client.client_secret, ACCESS_AUTHORIZATION_URL: `${base}/authorization`,
    ACCESS_TOKEN_URL: `${base}/token`, ACCESS_JWKS_URL: `${base}/jwks` };
}

/** The secrets the Worker still lacks. */
export const missingSecrets = present => SECRETS.filter(name => !present.includes(name));

/** What a run says: names and steps, never a value. */
export const reportLine = (step, done) => `ok ${step}${done ? ` (${done})` : ''}`;

/** Cloudflare's API as one call: its result, or an error with the status and Cloudflare's words, never the token. */
export function cloudflare(token, request) {
  return async (path, method = 'GET', body) => {
    const response = await request(`https://api.cloudflare.com/client/v4${path}`, {
      method, headers: { Authorization: `Bearer ${token}`, ...(body && { 'Content-Type': 'application/json' }) }, body: body && JSON.stringify(body),
    });
    const answer = await response.json().catch(() => ({}));
    if (!response.ok || !answer.success) {
      const error = new Error(`Cloudflare ${method} ${path.replace(/\/[0-9a-f-]{32,36}/g, '/…')}: ${response.status} ${answer.errors?.map(item => item.message).join('; ') ?? ''}`);
      error.status = response.status;
      throw error;
    }
    return answer.result;
  };
}

/** The permission groups the token holds, read from its own policy. */
async function grantedGroups(cf) {
  const { id } = await cf('/user/tokens/verify');
  const { policies } = await cf(`/user/tokens/${id}`);
  return policies.filter(policy => policy.effect === 'allow').flatMap(policy => policy.permission_groups.map(group => group.name));
}

const runWrangler = (args, input) => execFileSync('npx', ['wrangler', ...args, '-c', CONFIG], { cwd: APP, input,
  stdio: ['pipe', 'inherit', 'inherit'], env: { ...process.env, CI: '1' } });

/** One run. Cloudflare's API, wrangler and the output come in as arguments, so a test can stand in for each. */
export async function setup({ args, env, request = fetch, wrangler = runWrangler, log = console.log }) {
  const { staging, check } = parseArgs(args);
  const { CLOUDFLARE_API_TOKEN: token, CLOUDFLARE_ACCOUNT_ID: account } = env;
  if (!token || !/^[a-f0-9]{32}$/i.test(account ?? '')) throw new Error('CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID is missing from .env');
  const cf = cloudflare(token, request);
  const lines = permissionLines(await grantedGroups(cf));
  log(lines.join('\n'));
  if (lines.some(line => !line.startsWith('ok'))) throw new Error('the token lacks a permission above; widen it, then run again');
  if (check) return;

  const root = `/accounts/${account}`;
  const goal = target(parseConfig(join(APP, CONFIG)), staging);
  const environment = staging ? ['--env', 'staging'] : [];
  // The first deploy makes the sign-in store, which has no id in git; later deploys keep the one the Worker has.
  const exists = await cf(`${root}/workers/scripts/${goal.worker}/settings`).then(() => true, error => error.status === 404 ? false : Promise.reject(error));
  if (!exists) wrangler(['deploy', ...environment]);
  log(reportLine(`worker ${goal.worker}`, exists ? '' : 'deployed'));

  const apps = await cf(`${root}/access/apps?per_page=1000`);
  let app = apps.find(item => item.name === goal.app);
  const made = !app;
  if (made) app = await cf(`${root}/access/apps`, 'POST', saasApp(goal));
  const policies = await cf(`${root}/access/apps/${app.id}/policies`);
  if (!policies.length) await cf(`${root}/access/apps/${app.id}/policies`, 'POST', ownerPolicy(goal.owner));
  log(reportLine(`Access app "${goal.app}", owner only`, made ? 'made' : ''));

  const present = (await cf(`${root}/workers/scripts/${goal.worker}/secrets`)).map(secret => secret.name);
  const missing = missingSecrets(present);
  if (missing.length) {
    // Cloudflare shows a client secret only when it makes the app: a lost one means a new app.
    if (!made) throw new Error(`the Worker lacks ${missing.join(', ')}: delete the Access app "${goal.app}", then run again`);
    const { auth_domain: teamDomain } = await cf(`${root}/access/organizations`);
    wrangler(['secret', 'bulk', ...environment], JSON.stringify(signInValues(teamDomain, app.saas_app)));
  }
  log(reportLine('sign-in secrets', missing.length ? `put ${missing.join(', ')}` : ''));
  log(`Connect address: ${goal.address}`);
}

async function main() {
  const envFile = join(repoRoot, '.env');
  if (!process.env.CLOUDFLARE_API_TOKEN && existsSync(envFile)) process.loadEnvFile(envFile);
  await setup({ args: process.argv.slice(2), env: process.env });
}

if (isMain(import.meta.url)) main().catch(error => {
  console.error(`relay-mcp-setup: ${error.message}`);
  process.exitCode = 1;
});
