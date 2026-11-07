#!/usr/bin/env node
// Read-only publication gate. Never modifies an Access policy or publishes content.
import { createHash } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import { privateDeployment, accessConflicts } from './lib-access-config.mjs';
import { findWranglerConfig, lineAddressProblem, lineConfigPath, parseConfig, redirectedConfig } from './lib-wrangler-config.mjs';
import { isMain, parseCli, usageError } from './lib-cli.mjs';

// The routes the Worker checks the sign-in on itself; staging has no memory and no company knowledge.
const git = { behavior: 'public', path_pattern: '/api/access/code/git/*' };
const knowledge = { behavior: 'public', path_pattern: '/api/access/knowledge/git/*' };
// An install whose Access step ran before company knowledge holds the first set until it runs again.
const LIVE_SETS = [[{ behavior: 'public', path_pattern: '/_memory/*' }, git], [{ behavior: 'public', path_pattern: '/_memory/*' }, git, knowledge]];
// Public knowledge pages, on both apps; until the Access step runs again they stay behind the sign-in, which is closed.
const publicPages = { behavior: 'public', path_pattern: '/public/*' };
const SHARED = "previews still share the live app's sign-in; run setup's Access step (wiki/stack/employee-access.md#finish-access-setup) and publish";
const NO_PUBLIC = "public knowledge pages still ask for the sign-in; run setup's Access step once (wiki/stack/knowledge-reader.md#public-pages)";

export async function checkPrivateAccess(config, environment, cf, generated) {
  const production = privateDeployment(config, 'production');
  const staging = privateDeployment(config, 'staging');
  const target = environment === 'production' ? production : staging;
  if (generated && !isDeepStrictEqual(privateDeployment(generated, environment), target)) throw new Error('built configuration differs from the protected source Worker');
  if (production.open || staging.open) return checkOpen(config, environment, cf, production, staging);
  if (production.teamDomain !== staging.teamDomain || production.workerId === staging.workerId) throw new Error('production and staging need one team and distinct Workers');
  // A shared app lets a preview's sign-in open the live app: previews stop, and the live app publishes with a warning.
  const shared = production.appId === staging.appId && production.audience === staging.audience;
  if (shared ? environment === 'staging' : production.appId === staging.appId || production.audience === staging.audience) {
    throw new Error(shared ? SHARED : 'production and staging must each have their own private app');
  }
  const account = config.account_id ?? process.env.CLOUDFLARE_ACCOUNT_ID;
  if (!/^[a-f0-9]{32}$/i.test(account ?? '')) throw new Error('the Cloudflare account ID is missing');
  const root = `/accounts/${account}`;
  const list = async path => {
    const items = [];
    for (let page = 1; ; page++) {
      const batch = await cf(`${path}?per_page=50&page=${page}`);
      if (!Array.isArray(batch)) throw new Error('provider resource list is unavailable');
      items.push(...batch);
      if (batch.length < 50) return items;
    }
  };
  const workers = [];
  for (const expected of [production, staging]) {
    const worker = await cf(`${root}/workers/workers/${expected.name}`);
    if (worker.id !== expected.workerId || worker.name !== expected.name) throw new Error('the actual Worker ID does not match protected configuration');
    workers.push(worker);
    const secrets = await cf(`${root}/workers/scripts/${expected.name}/secrets`);
    if (!Array.isArray(secrets) || secrets.some(secret => ['SKIP_AUTH', 'WONG_ENVIRONMENT'].includes(secret.name))) throw new Error('deployed secrets override authentication configuration');
  }
  const scripts = await cf(`${root}/workers/scripts`);
  for (const worker of workers) worker.routes = scripts.find(script => script.id === worker.name)?.routes ?? [];
  const { subdomain } = await cf(`${root}/workers/subdomain`);
  if (!subdomain) throw new Error('the default Worker hostname is unavailable');
  const appPath = `${root}/access/apps/${target.appId}`;
  const app = await cf(appPath);
  const host = `${target.name}.${subdomain}.workers.dev`;
  const desired = overrides => [
    { type: 'worker', worker_id: target.workerId, overrides },
    ...(shared ? [{ type: 'worker', worker_id: staging.workerId, overrides: [git] }] : []),
    { type: 'public', uri: host, overrides },
  ];
  const destinations = app.destinations ?? [];
  const covered = overrides => destinations.length === desired(overrides).length && desired(overrides).every(item => destinations.some(value => isDeepStrictEqual(value, item)));
  const sets = target === production ? LIVE_SETS : [[git]];
  const opened = sets.map(set => [...set, publicPages]).some(covered);
  if (app.id !== target.appId || app.aud !== target.audience || app.type !== 'self_hosted' || app.domain !== host || !(opened || sets.some(covered))) throw new Error('Access coverage or its memory and git exceptions are missing or broader than this workspace');
  const policies = await list(`${appPath}/policies`);
  checkPolicies(policies, app);
  const checkerKey = await checkCheckerKey(config, environment, policies, id => cf(`${root}/access/service_tokens/${id}`));
  if (accessConflicts(await list(`${root}/access/apps`), workers, subdomain, [production.appId, staging.appId]).length) throw new Error('another Access application overlaps this workspace; review hostname/path/preview precedence');
  const warning = [shared && SHARED, !opened && NO_PUBLIC].filter(Boolean).join('; ');
  return { environment, worker: target.name, protection: 'configured', humanLogin: 'unverified', ...(checkerKey && { checkerKey }), ...(warning && { warning }) };
}

/** Relay's Worker lets in only the one service token whose Client ID has the SHA-256 each environment's
 *  committed var holds: git keeps the fingerprint, never the Client ID. */
export const RELAY_CHECKER_VAR = 'RELAY_CHECKER_SHA256';
const sha256 = text => createHash('sha256').update(text).digest('hex');
const relayVars = (config, environment) => (environment === 'staging' ? config.env?.staging?.vars : config.vars) ?? {};

/** Compares the checker policy's token with the var, so a new checker key from /verify or setup fails here and names
 *  the fix, not later as a 403 on every check. Messages name fingerprints alone; the secret is never read.
 *  Returns undefined without Relay, 'matches', or 'unverified' when this credential may not read service tokens. */
export async function checkCheckerKey(config, environment, policies, readToken) {
  const relay = [config.vars, config.env?.staging?.vars].some(vars => vars && RELAY_CHECKER_VAR in vars);
  if (!relay) return undefined;
  const expected = relayVars(config, environment)[RELAY_CHECKER_VAR];
  const where = `app/wrangler.jsonc (${environment === 'staging' ? 'env.staging.vars' : 'vars'})`;
  if (!expected) throw new Error(`${RELAY_CHECKER_VAR} is missing for ${environment}; set it in ${where} to the SHA-256 of the checker key's Client ID`);
  const checker = policies.find(policy => policy.decision === 'non_identity');
  let token;
  try {
    token = await readToken(checker.include[0].service_token.token_id);
  } catch (error) {
    // The CI deploy key holds Access: Apps and Policies Read alone; a host run with the user token checks it.
    if (error.status === 403) return 'unverified';
    throw error;
  }
  const actual = token?.client_id ? sha256(token.client_id) : '(unknown)';
  if (actual !== expected) {
    throw new Error(`the ${environment} checker key changed: set ${RELAY_CHECKER_VAR} in ${where} to ${actual} and publish, or Relay Everything refuses every check`);
  }
  return 'matches';
}

const tokensOnly = (policy, count) => Array.isArray(policy.include) && policy.include.length === count &&
  policy.include.every(rule => Object.keys(rule).length === 1 && !!rule.service_token?.token_id);

/** One human policy of exact reachable emails and one machine policy of one service token, each attached to the app
 *  and with no exclude or require rule. */
export function checkPolicies(policies, app) {
  const human = policies.filter(policy => policy.decision === 'allow');
  const machine = policies.filter(policy => policy.decision === 'non_identity');
  const reviewed = [...human, ...machine];
  if (policies.length !== reviewed.length || human.length !== 1 || machine.length !== 1 || !reviewed.every(policy => app.policies?.some(attached => attached.id === policy.id))) throw new Error('the separate human and machine policies are missing or unreviewed');
  if (human[0].include?.length < 1 || !Array.isArray(human[0].include) || human[0].include.some(rule => Object.keys(rule).length !== 1 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(rule.email?.email ?? '') || /(?:\.invalid|@(?:[^@]*\.)?noreply\.github\.com)$/i.test(rule.email.email)) || !tokensOnly(machine[0], 1) || policies.some(policy => (policy.exclude?.length ?? 0) || (policy.require?.length ?? 0))) throw new Error('workspace policies must use exact reachable emails and one separate service token');
}

const OPEN_WARNING = 'this workspace is open without login: anyone with its link can see it. Add a card to Cloudflare and rerun provision to make it private: wiki/stack/cloudflare-access.md#open-until-the-card';

/** Open until the card: no Access to check, but the Workers and secrets rule still hold. */
async function checkOpen(config, environment, cf, production, staging) {
  if (!production.open || !staging.open) throw new Error('production and staging must both be private or both open without login');
  if (!production.name || !staging.name || production.name === staging.name) throw new Error('production and staging need distinct Worker names');
  const account = config.account_id ?? process.env.CLOUDFLARE_ACCOUNT_ID;
  if (!/^[a-f0-9]{32}$/i.test(account ?? '')) throw new Error('the Cloudflare account ID is missing');
  const root = `/accounts/${account}`;
  // The first deploy creates the Workers, so check secrets only on those that exist.
  const scripts = await cf(`${root}/workers/scripts`);
  if (!Array.isArray(scripts)) throw new Error('provider resource list is unavailable');
  for (const name of [production.name, staging.name]) {
    if (!scripts.some(script => script.id === name)) continue;
    const secrets = await cf(`${root}/workers/scripts/${name}/secrets`);
    if (!Array.isArray(secrets) || secrets.some(secret => ['SKIP_AUTH', 'WONG_ENVIRONMENT'].includes(secret.name))) throw new Error('deployed secrets override authentication configuration');
  }
  return { environment, worker: environment === 'production' ? production.name : staging.name, protection: 'open', humanLogin: 'none' };
}

/** Refuses a live line Worker that would answer on a web address: it needs no Access app because it has none. */
export function checkLineAddress(configPath) {
  const line = lineConfigPath(configPath);
  const problem = line && lineAddressProblem(parseConfig(line));
  if (problem) throw new Error(`the live line's Worker config: ${problem}`);
}

async function main() {
  const usage = 'usage: node scripts/check-private-access.mjs --environment <production|staging> [--source-only]';
  const { values } = parseCli({ usage, options: { environment: { type: 'string' }, 'source-only': { type: 'boolean' } } });
  if (!['production', 'staging'].includes(values.environment)) usageError(usage);
  if (!process.env.CLOUDFLARE_API_TOKEN) throw new Error('the CI/host Cloudflare credential is missing');
  const path = findWranglerConfig();
  checkLineAddress(path);
  const redirected = values['source-only'] ? null : redirectedConfig(path);
  const cf = async route => {
    const response = await fetch(`https://api.cloudflare.com/client/v4${route}`, { headers: { Authorization: `Bearer ${process.env.CLOUDFLARE_API_TOKEN}` } });
    const body = await response.json();
    if (!response.ok || !body.success) throw Object.assign(new Error(`Cloudflare read-only protection check failed (${response.status}); finish private setup or restore CI Access: Apps and Policies Read`), { status: response.status });
    return body.result;
  };
  const result = await checkPrivateAccess(parseConfig(path), values.environment, cf, redirected && parseConfig(redirected));
  if (result.protection === 'open') console.warn(`private-access: WARNING ${OPEN_WARNING}`);
  if (result.warning) console.warn(`private-access: WARNING ${result.warning}`);
  console.log(JSON.stringify(result));
}
if (isMain(import.meta.url)) main().catch(error => {
  console.error(`private-access: ${error.message}; no content or preview published`);
  process.exitCode = 1;
});
