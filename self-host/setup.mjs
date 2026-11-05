#!/usr/bin/env node
// Relay in a person's own Cloudflare account: the Relay-only Worker and page, its database, bucket and queue, the AI
// connector, and the Access login for the owner's email. Each step is skipped when done. self-host/SETUP.md
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isMain, parseCli, usageError } from '../scripts/lib-cli.mjs';
import { redirectedConfig, stripJsonc } from '../scripts/lib-wrangler-config.mjs';
import { cloudflare, ownerPolicy, saasApp, signInValues } from '../scripts/relay-mcp-setup.mjs';

const USAGE = `usage: node self-host/setup.mjs <check|install|update|status|remove> [--email <you>] [--name <name>] [--yes]
  check                       check the Cloudflare key and account; make nothing
  install --email <you>       make your Relay server; your email is its only login
  update                      apply new database changes, then put the newest Relay live; your data stays
  status                      your server's address, and whether each part answers
  remove --yes                delete your Relay server and all its data; this can't be undone
  --name <name>               the server's name in Cloudflare (default relay)`;

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = join(HERE, '..', 'app');
export const FILES = { config: join(HERE, 'wrangler.jsonc'), mcp: join(HERE, 'wrangler.mcp.jsonc'), env: join(HERE, '.env') };
// The Pebble signing secret's page stays on this computer, outside the repository, readable only by you.
const PRIVATE = join(homedir(), '.relay-everything', 'self-host');

/** What each part's name is, from the install's name. */
export const names = name => ({ worker: name, database: `${name}-db`, bucket: `${name}-notes`, queue: `${name}-webhooks`, mcp: `${name}-mcp`,
  app: `Relay (${name})`, mcpApp: `Relay AI connector (${name})` });

/** Each part `check` reads, the Cloudflare permission that reads it, and what to do when it is off. */
export const PARTS = [
  ['Workers', '/workers/subdomain', 'Workers Scripts Write', 'open Workers & Pages once in the Cloudflare dashboard to get a workers.dev address'],
  ['D1 database', '/d1/database', 'D1 Write'],
  ['R2 bucket', '/r2/buckets', 'Workers R2 Storage Write', 'turn on R2 once in the Cloudflare dashboard (R2 Object Storage)'],
  ['Queues', '/queues', 'Queues Write'],
  ['KV', '/storage/kv/namespaces', 'Workers KV Storage Write'],
  ['Access apps', '/access/apps', 'Access: Apps and Policies Write'],
  ['Access service tokens', '/access/service_tokens', 'Access: Service Tokens Write'],
  ['Zero Trust', '/access/organizations', 'Access: Organizations, Identity Providers, and Groups Read',
    'turn on Zero Trust once in the Cloudflare dashboard (the Free plan) and pick a team name'],
];

export function parseCommand(args) {
  const [command, ...rest] = args;
  if (!['check', 'install', 'update', 'status', 'remove'].includes(command)) return { problem: 'name a command: check, install, update, status or remove' };
  const { values } = parseCli({ usage: USAGE, args: rest, options: { email: { type: 'string' }, name: { type: 'string' }, yes: { type: 'boolean' } } });
  const name = values.name ?? 'relay';
  if (!/^[a-z][a-z0-9-]{1,40}[a-z0-9]$/.test(name)) return { problem: '--name takes 3 to 42 lowercase letters, digits and hyphens' };
  if (command === 'install' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.email ?? '')) return { problem: 'install needs --email, the address you sign in with' };
  return { command, name, email: values.email, yes: !!values.yes };
}

/** One line per part: `ok`, or what to add or turn on. A 403 is a missing permission; another refusal is a part
 *  Cloudflare hasn't turned on, or a team with no Zero Trust. */
export async function checkLines(cf, root) {
  const lines = [];
  for (const [part, path, permission, turnOn] of PARTS) {
    const problem = await cf(`${root}${path}`).then(result => part === 'Zero Trust' && !result?.auth_domain ? 'off' : null,
      error => error.status === 403 && !/not enabled|enable|subscription/i.test(error.message) ? 'permission' : 'off');
    lines.push(!problem ? `ok ${part}`
      : problem === 'permission' || !turnOn ? `missing ${part}: add "${permission}" to the token` : `missing ${part}: ${turnOn}`);
  }
  return lines;
}

/** The install's two configs, from the committed templates: names, IDs and the owner, and nothing secret. */
export function configs(template, mcpTemplate, { name, email, account, database, subdomain, team, access, workerId = '' }) {
  const part = names(name);
  const app = JSON.parse(stripJsonc(template));
  Object.assign(app, { name: part.worker, account_id: account });
  Object.assign(app.vars, { WONG_OWNER_EMAIL: email, CF_ACCESS_TEAM_DOMAIN: team, CF_ACCESS_AUD: access.aud, CF_ACCESS_APP_ID: access.id, CF_ACCESS_WORKER_ID: workerId });
  Object.assign(app.d1_databases[0], { database_name: part.database, database_id: database });
  app.r2_buckets[0].bucket_name = part.bucket;
  app.queues.producers[0].queue = app.queues.consumers[0].queue = part.queue;
  app.services[0].service = part.mcp;
  const mcp = JSON.parse(stripJsonc(mcpTemplate));
  Object.assign(mcp, { name: part.mcp, account_id: account });
  Object.assign(mcp.vars, { WONG_OWNER_EMAIL: email, RELAY_MCP_ADDRESS: `https://${part.mcp}.${subdomain}.workers.dev/mcp` });
  Object.assign(mcp.d1_databases[0], { database_name: part.database, database_id: database });
  return { app, mcp };
}

/** The login: a self-hosted Access app on the server's address and, once it is live, the Worker itself, with the owner's
 *  email as its one person. Device keys join its "Relay devices" policy when relay-device-key.mjs makes them. */
export const accessApp = (app, host, workerId) => ({ name: app, type: 'self_hosted', domain: host,
  destinations: [...(workerId ? [{ type: 'worker', worker_id: workerId }] : []), { type: 'public', uri: host }],
  session_duration: '730h', app_launcher_visible: false });

/** The private page that holds the Pebble signing secret, for the Pebble app's Sign requests setting. */
export const signingPage = (server, secret) => `<!doctype html><meta charset="utf-8"><title>Relay: Pebble signing secret</title>
<h1>Pebble signing secret</h1><p>For ${server}. In the Pebble app's webhook, turn on Sign requests and enter:</p><p><code>${secret}</code></p>`;

const readTemplate = file => readFileSync(join(HERE, file), 'utf8');
const writeJson = (file, value) => writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
const runWrangler = (args, input, env) => execFileSync('npx', ['wrangler', ...args], { cwd: APP, input, stdio: ['pipe', 'inherit', 'inherit'], env: { ...env, CI: '1' } });
const runBuild = files => execFileSync('npm', ['run', 'build:relay-only'], { cwd: APP, stdio: ['ignore', 'inherit', 'inherit'],
  env: { ...process.env, RELAY_CONFIG: files.config } });

/** Find a part by its name in a list, or make it. */
async function ensure(list, find, make) {
  return (await list()).find(find) ?? await make();
}

/** Put the server live: migrations first, so a failed one leaves the old server running; then the connector, which the
 *  server binds; then the server. */
function deploy({ wrangler, build, files }, database) {
  wrangler(['d1', 'migrations', 'apply', database, '--remote', '-c', files.config]);
  wrangler(['deploy', '-c', files.mcp]);
  build();
  // The build writes the server's config where its redirect file says, beside app/'s own.
  wrangler(['deploy', '-c', redirectedConfig(join(APP, 'wrangler.jsonc'))]);
}

async function install(io, cf, root, { name, email, account }) {
  const part = names(name);
  const { subdomain } = await cf(`${root}/workers/subdomain`);
  const { auth_domain: team } = await cf(`${root}/access/organizations`);
  const host = `${part.worker}.${subdomain}.workers.dev`;
  const database = await ensure(() => cf(`${root}/d1/database?name=${part.database}`), item => item.name === part.database,
    () => cf(`${root}/d1/database`, 'POST', { name: part.database }));
  await ensure(async () => (await cf(`${root}/r2/buckets`)).buckets ?? [], item => item.name === part.bucket,
    () => cf(`${root}/r2/buckets`, 'POST', { name: part.bucket }));
  await ensure(() => cf(`${root}/queues`), item => item.queue_name === part.queue, () => cf(`${root}/queues`, 'POST', { queue_name: part.queue }));
  const apps = await cf(`${root}/access/apps?per_page=1000`);
  const access = apps.find(item => item.name === part.app) ?? await cf(`${root}/access/apps`, 'POST', accessApp(part.app, host));
  if (!(await cf(`${root}/access/apps/${access.id}/policies`)).length) await cf(`${root}/access/apps/${access.id}/policies`, 'POST', ownerPolicy(email));
  io.log('ok database, bucket, queue and login');

  const settings = { name, email, account, database: database.uuid, subdomain, team, access };
  const filled = more => configs(readTemplate('wrangler.template.jsonc'), readTemplate('mcp.template.jsonc'), { ...settings, ...more });
  const { app, mcp } = filled();
  writeJson(io.files.config, app);
  writeJson(io.files.mcp, mcp);
  deploy(io, part.database);
  // The Worker's ID exists only once it is live; the login covers it, and the key command checks it.
  const workerId = (await cf(`${root}/workers/workers/${part.worker}`)).id;
  if (!access.destinations?.some(item => item.type === 'worker')) await cf(`${root}/access/apps/${access.id}`, 'PUT', accessApp(part.app, host, workerId));
  writeJson(io.files.config, filled({ workerId }).app);
  io.log('ok server and AI connector live');

  const secrets = async worker => (await cf(`${root}/workers/scripts/${worker}/secrets`)).map(secret => secret.name);
  if (!(await secrets(part.worker)).includes('RELAY_PEBBLE_SIGNING')) {
    const secret = randomBytes(32).toString('hex');
    io.wrangler(['secret', 'put', 'RELAY_PEBBLE_SIGNING', '-c', io.files.config], secret);
    mkdirSync(PRIVATE, { recursive: true, mode: 0o700 });
    writeFileSync(join(PRIVATE, `${name}-pebble-signing.html`), signingPage(`https://${host}`, secret), { mode: 0o600 });
    io.log(`ok Pebble signing secret, on your private page: ${join(PRIVATE, `${name}-pebble-signing.html`)}`);
  }
  if (!(await secrets(part.mcp)).includes('ACCESS_CLIENT_ID')) {
    const callback = `https://${part.mcp}.${subdomain}.workers.dev/callback`;
    const old = apps.find(item => item.name === part.mcpApp);
    if (old) await cf(`${root}/access/apps/${old.id}`, 'DELETE');
    const sso = await cf(`${root}/access/apps`, 'POST', saasApp({ app: part.mcpApp, callback }));
    await cf(`${root}/access/apps/${sso.id}/policies`, 'POST', ownerPolicy(email));
    io.wrangler(['secret', 'bulk', '-c', io.files.mcp], JSON.stringify(signInValues(team, sso.saas_app)));
    io.log('ok AI connector sign-in');
  }
  io.log(`server=https://${host}`);
  io.log(`connector=${mcp.vars.RELAY_MCP_ADDRESS}`);
}

async function status(io, cf, root, name, request) {
  const part = names(name);
  const exists = path => cf(`${root}${path}`).then(() => true, () => false);
  const checks = { server: `/workers/scripts/${part.worker}/settings`, connector: `/workers/scripts/${part.mcp}/settings`,
    database: `/d1/database?name=${part.database}`, bucket: `/r2/buckets/${part.bucket}`, queue: `/queues?name=${part.queue}` };
  const found = {};
  for (const [label, path] of Object.entries(checks)) found[label] = await exists(path);
  found.database &&= (await cf(`${root}${checks.database}`)).some(item => item.name === part.database);
  found.queue &&= (await cf(`${root}/queues`)).some(item => item.queue_name === part.queue);
  for (const [label, here] of Object.entries(found)) io.log(`${here ? 'ok' : 'none'} ${label}`);
  if (found.server) {
    const { subdomain } = await cf(`${root}/workers/subdomain`);
    const answer = await request(`https://${part.worker}.${subdomain}.workers.dev/`, { redirect: 'manual' }).catch(() => null);
    io.log(`${answer && answer.status < 500 ? 'ok' : 'down'} login page`);
    io.log(`server=https://${part.worker}.${subdomain}.workers.dev`);
  }
  return Object.values(found).some(Boolean);
}

async function remove(io, cf, root, name, yes) {
  const part = names(name);
  const plan = [`Workers ${part.worker} and ${part.mcp}`, `D1 database ${part.database} (every note, health sample and place)`,
    `R2 bucket ${part.bucket} (every recording)`, `queue ${part.queue}`, `Access apps "${part.app}" and "${part.mcpApp}", and their device keys`];
  if (!yes) {
    io.log(`remove would delete, and this can't be undone:\n${plan.map(line => `- ${line}`).join('\n')}`);
    io.log('Run it again with --yes to delete.');
    return false;
  }
  const quiet = promise => promise.catch(error => (error.status === 404 ? null : Promise.reject(error)));
  const apps = await cf(`${root}/access/apps?per_page=1000`);
  for (const app of apps.filter(item => [part.app, part.mcpApp].includes(item.name))) {
    const tokens = (await cf(`${root}/access/apps/${app.id}/policies`)).flatMap(policy => policy.include ?? []).map(rule => rule.service_token?.token_id).filter(Boolean);
    await cf(`${root}/access/apps/${app.id}`, 'DELETE');
    for (const token of tokens) await quiet(cf(`${root}/access/service_tokens/${token}`, 'DELETE'));
  }
  const kv = (await quiet(cf(`${root}/workers/scripts/${part.mcp}/settings`)))?.bindings?.filter(binding => binding.type === 'kv_namespace') ?? [];
  // Cloudflare keeps a Worker that reads a queue, and a queue a Worker sends to: detach the reader, then the Worker.
  const queue = (await cf(`${root}/queues`)).find(item => item.queue_name === part.queue);
  if (queue) for (const reader of await cf(`${root}/queues/${queue.queue_id}/consumers`)) await cf(`${root}/queues/${queue.queue_id}/consumers/${reader.consumer_id}`, 'DELETE');
  for (const worker of [part.worker, part.mcp]) await quiet(cf(`${root}/workers/scripts/${worker}?force=true`, 'DELETE'));
  for (const binding of kv) await quiet(cf(`${root}/storage/kv/namespaces/${binding.namespace_id}`, 'DELETE'));
  if (queue) await cf(`${root}/queues/${queue.queue_id}`, 'DELETE');
  for (const item of (await cf(`${root}/d1/database?name=${part.database}`)).filter(item => item.name === part.database)) await cf(`${root}/d1/database/${item.uuid}`, 'DELETE');
  if (await cf(`${root}/r2/buckets/${part.bucket}`).then(() => true, () => false)) {
    // A bucket deletes only when empty, and Cloudflare's API lists objects but doesn't delete them; wrangler does.
    for (const object of await cf(`${root}/r2/buckets/${part.bucket}/objects`).catch(() => [])) io.wrangler(['r2', 'object', 'delete', `${part.bucket}/${object.key}`, '--remote']);
    await cf(`${root}/r2/buckets/${part.bucket}`, 'DELETE');
  }
  for (const file of [io.files.config, io.files.mcp]) rmSync(file, { force: true });
  io.log(`deleted:\n${plan.map(line => `- ${line}`).join('\n')}`);
  return true;
}

/** The account the token reaches: the one named in .env, or the token's only account. */
async function accountOf(cf, env) {
  if (/^[a-f0-9]{32}$/i.test(env.CLOUDFLARE_ACCOUNT_ID ?? '')) return env.CLOUDFLARE_ACCOUNT_ID;
  const accounts = await cf('/accounts');
  if (accounts.length !== 1) throw new Error(`the token reaches ${accounts.length} accounts; put CLOUDFLARE_ACCOUNT_ID in self-host/.env`);
  return accounts[0].id;
}

/** One run. Cloudflare's API, wrangler, the build and the output come in as arguments, so a test can stand in for each. */
export async function setup({ args, env, request = fetch, wrangler = runWrangler, build = runBuild, log = console.log, files = FILES }) {
  const parsed = parseCommand(args);
  if (parsed.problem) throw Object.assign(new Error(parsed.problem), { usage: true });
  if (!env.CLOUDFLARE_API_TOKEN) throw new Error('CLOUDFLARE_API_TOKEN is missing: put it in self-host/.env (SETUP.md)');
  const cf = cloudflare(env.CLOUDFLARE_API_TOKEN, request);
  const account = await accountOf(cf, env);
  const root = `/accounts/${account}`;
  const io = { wrangler: (more, input) => wrangler(more, input, { ...env, CLOUDFLARE_ACCOUNT_ID: account }), build: () => build(files), log, files };
  const installed = existsSync(files.config) && JSON.parse(readFileSync(files.config, 'utf8'));
  const name = installed && !args.includes('--name') ? installed.name : parsed.name;

  if (parsed.command === 'check' || parsed.command === 'install') {
    const lines = await checkLines(cf, root);
    log(lines.join('\n'));
    if (lines.some(line => !line.startsWith('ok'))) return 'refused';
    if (parsed.command === 'check') return 'ok';
    await install(io, cf, root, { name, email: parsed.email, account });
    return 'ok';
  }
  if (parsed.command === 'update') {
    if (!installed) throw new Error('no install here: run install first, or copy self-host/wrangler.jsonc and wrangler.mcp.jsonc back');
    deploy(io, installed.d1_databases[0].database_name);
    log('ok database changes applied, then the newest Relay put live');
    return 'ok';
  }
  if (parsed.command === 'status') return await status(io, cf, root, name, request) ? 'ok' : 'none';
  return await remove(io, cf, root, name, parsed.yes) ? 'ok' : 'refused';
}

async function main() {
  if (!process.env.CLOUDFLARE_API_TOKEN && existsSync(FILES.env)) process.loadEnvFile(FILES.env);
  try {
    console.log(`result=${await setup({ args: process.argv.slice(2), env: process.env })}`);
  } catch (error) {
    if (error.usage) usageError(USAGE, error.message);
    console.error(`setup: ${error.message}`);
    console.log('result=failed');
    process.exitCode = 1;
  }
}

if (isMain(import.meta.url)) main();
