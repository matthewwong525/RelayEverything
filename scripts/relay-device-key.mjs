#!/usr/bin/env node
// Relay's device keys: one Cloudflare Access service token per phone, Pebble app or Claude Code computer, held in the
// Access app's "Relay devices" policy and listed in relay_devices, which the Worker reads. A Claude Code key only sends chats.
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { isMain, parseCli, usageError } from './lib-cli.mjs';
import { privateDeployment } from './lib-access-config.mjs';
import { findWranglerConfig, parseConfig, repoRoot } from './lib-wrangler-config.mjs';
import { RELAY_DEVICES } from './check-private-access.mjs';

const USAGE = `usage: node scripts/relay-device-key.mjs <create|list|revoke> [--name <device>] [--for claude-code] [--staging] [--server <url>]
  create --name "Android phone"   make a key; it shows once, as a QR code in your own terminal and on a private page
  create --name "Laptop" --for claude-code
                                  make a key that only sends Claude Code chats; its connect code shows once, as text
  list                            every key: its name, what it is for, when it was made, and whether it is turned off
  revoke --name "Android phone"   turn a key off at once, then delete it from Cloudflare
  --staging                       the previews' Access app and database, not the live ones`;

/** What each --for makes: the key's reach in relay_devices and its token's name in Cloudflare. */
const KINDS = { phone: { reaches: 'phone', token: 'device' }, 'claude-code': { reaches: 'chats', token: 'chats' } };

const NAME = /^[\p{L}\p{N}][\p{L}\p{N} '’._-]{0,39}$/u;
// Hand-over pages stay on this computer, outside the repository, readable only by you.
export const HAND_OVER = join(homedir(), '.relay-ring', 'device-keys');

/** The command and its flags, or a usage message. */
export function parseCommand(args) {
  const [command, ...rest] = args;
  if (!['create', 'list', 'revoke'].includes(command)) return { problem: 'name a command: create, list or revoke' };
  const { values } = parseCli({ usage: USAGE, args: rest,
    options: { name: { type: 'string' }, staging: { type: 'boolean' }, server: { type: 'string' }, for: { type: 'string' } } });
  const name = values.name?.trim();
  if (command !== 'list' && !NAME.test(name ?? '')) return { problem: '--name takes 1 to 40 letters, digits, spaces and . _ - \'' };
  if (values.server !== undefined && !/^https:\/\/[^/\s]+$/.test(values.server)) return { problem: '--server takes an https:// address with no path' };
  const kind = values.for ?? 'phone';
  if (!Object.hasOwn(KINDS, kind)) return { problem: '--for takes claude-code, or nothing for a phone or the Pebble app' };
  return { command, name, staging: !!values.staging, server: values.server, kind };
}

/** The policy's rules with one token added, or with one taken out. */
export const withToken = (include, tokenId) => [...include.filter(rule => rule.service_token?.token_id !== tokenId), { service_token: { token_id: tokenId } }];
export const withoutToken = (include, tokenId) => include.filter(rule => rule.service_token?.token_id !== tokenId);

/** What the phone's Connect screen scans or takes pasted. */
export const connectCode = ({ server, clientId, clientSecret }) => JSON.stringify({ relay: 1, server, clientId, clientSecret });

const escape = text => text.replace(/[&<>"']/g, char => `&#${char.charCodeAt(0)};`);

/** The private page: the QR code, then each value to copy, for a phone or the Pebble app's two headers. */
export function handOverPage({ name, server, clientId, clientSecret, qrSvg }) {
  const row = (label, value) => `<dt>${escape(label)}</dt><dd><code>${escape(value)}</code></dd>`;
  return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Relay key: ${escape(name)}</title>
<style>body{font:16px system-ui;max-width:40rem;margin:2rem auto;padding:0 1rem}code{word-break:break-all}dd{margin:0 0 1rem}svg{width:16rem;height:auto}</style>
<h1>Relay key: ${escape(name)}</h1>
<p>This key shows only here. Delete this file when the device is connected.</p>
<h2>A phone</h2>
<p>Open the Relay app and tap Scan the QR code, then scan this code.</p>
${qrSvg ?? '<p>No QR code: install qrencode, or paste the values below.</p>'}
<h2>The Pebble app, or by hand</h2>
<dl>${row('Server', server)}${row('Webhook address', `${server}/apps/relay/api/pebble`)}${row('CF-Access-Client-Id', clientId)}${row('CF-Access-Client-Secret', clientSecret)}</dl>
`;
}

/** The private page of a Claude Code key: the connect code to paste when Claude Code asks for it. */
export function chatHandOverPage({ name, code }) {
  return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Relay chat key: ${escape(name)}</title>
<style>body{font:16px system-ui;max-width:40rem;margin:2rem auto;padding:0 1rem}code{word-break:break-all}</style>
<h1>Relay chat key: ${escape(name)}</h1>
<p>This key shows only here. Delete this file when Claude Code is connected.</p>
<p>In Claude Code, add the Relay plugin, then paste this connect code when it asks. The key can only send chats.</p>
<p><code>${escape(code)}</code></p>
`;
}

/** One line per key, with no secret: a client id names a key and opens nothing alone. */
export function listing(rows) {
  if (!rows.length) return 'No device keys yet. Make one: node scripts/relay-device-key.mjs create --name "Android phone"';
  const day = ms => new Date(ms).toISOString().slice(0, 10);
  const kind = reaches => reaches === 'chats' ? 'claude-code' : 'phone';
  return rows.map(row => `${row.name}\t${kind(row.reaches)}\tmade ${day(row.created_at)}\t${row.revoked_at === null ? 'on' : `turned off ${day(row.revoked_at)}`}\t${row.token_client_id}`).join('\n');
}

/** A file-safe name for the hand-over page. */
export const slug = name => name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'device';

function qr(text, type) {
  try {
    return execFileSync('qrencode', ['-t', type, '-m', '2', '-o', '-'], { input: text, encoding: 'utf8' });
  } catch {
    return null;
  }
}

function cloudflare(token) {
  return async (path, method = 'GET', body) => {
    const response = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
      method, headers: { Authorization: `Bearer ${token}`, ...(body && { 'Content-Type': 'application/json' }) }, body: body && JSON.stringify(body),
    });
    const answer = await response.json().catch(() => ({}));
    // Cloudflare's error words name the problem, never the token.
    if (!response.ok || !answer.success) throw new Error(`Cloudflare ${method} ${path.replace(/\/[0-9a-f-]{32,36}/g, '/…')}: ${response.status} ${answer.errors?.map(error => error.message).join('; ') ?? ''}`);
    return answer.result;
  };
}

function target(staging) {
  const config = parseConfig(findWranglerConfig());
  const environment = staging ? 'staging' : 'production';
  const { appId, name } = privateDeployment(config, environment);
  const database = (staging ? config.env?.staging : config).d1_databases?.find(entry => entry.binding === 'DB')?.database_id;
  const account = config.account_id ?? process.env.CLOUDFLARE_ACCOUNT_ID;
  if (!appId || !database || !/^[a-f0-9]{32}$/i.test(account ?? '')) throw new Error(`the ${environment} Access app, database or account id is missing`);
  return { appId, database, account, worker: name };
}

async function main() {
  const parsed = parseCommand(process.argv.slice(2));
  if (parsed.problem) usageError(USAGE, parsed.problem);
  const envFile = join(repoRoot, '.env');
  if (!process.env.CLOUDFLARE_API_TOKEN && existsSync(envFile)) process.loadEnvFile(envFile);
  if (!process.env.CLOUDFLARE_API_TOKEN) throw new Error('CLOUDFLARE_API_TOKEN is missing from .env');
  const cf = cloudflare(process.env.CLOUDFLARE_API_TOKEN);
  const { appId, database, account, worker } = target(parsed.staging);
  const root = `/accounts/${account}`;
  const sql = async (query, ...params) => (await cf(`${root}/d1/database/${database}/query`, 'POST', { sql: query, params }))[0].results;
  const policies = `${root}/access/apps/${appId}/policies`;
  const devicesPolicy = async () => (await cf(`${policies}?per_page=1000`)).find(policy => policy.name === RELAY_DEVICES && policy.decision === 'non_identity');

  if (parsed.command === 'list') return console.log(listing(await sql('SELECT name, reaches, token_client_id, created_at, revoked_at FROM relay_devices ORDER BY created_at')));

  const active = await sql('SELECT id, token_id, token_client_id FROM relay_devices WHERE name = ? AND revoked_at IS NULL', parsed.name);
  if (parsed.command === 'revoke') {
    if (!active.length) throw new Error(`no key named "${parsed.name}" is on`);
    for (const device of active) {
      // Turned off in the database first: the Worker refuses it from this moment, whatever Cloudflare does next.
      await sql('UPDATE relay_devices SET revoked_at = ? WHERE id = ?', Date.now(), device.id);
      const policy = await devicesPolicy();
      const include = policy ? withoutToken(policy.include, device.token_id) : [];
      if (policy && include.length) await cf(`${policies}/${policy.id}`, 'PUT', { name: policy.name, decision: policy.decision, include, precedence: policy.precedence });
      else if (policy) await cf(`${policies}/${policy.id}`, 'DELETE');
      await cf(`${root}/access/service_tokens/${device.token_id}`, 'DELETE');
    }
    return console.log(`Turned off and deleted the key "${parsed.name}".`);
  }

  if (active.length) throw new Error(`a key named "${parsed.name}" is already on; revoke it first or pick another name`);
  const server = parsed.server ?? `https://${worker}.${(await cf(`${root}/workers/subdomain`)).subdomain}.workers.dev`;
  const kind = KINDS[parsed.kind];
  const token = await cf(`${root}/access/service_tokens`, 'POST', { name: `relay-ring ${kind.token} ${parsed.name}`, duration: '8760h' });
  try {
    const policy = await devicesPolicy();
    if (policy) await cf(`${policies}/${policy.id}`, 'PUT', { name: policy.name, decision: policy.decision, include: withToken(policy.include, token.id), precedence: policy.precedence });
    else {
      const precedence = Math.max(0, ...(await cf(`${policies}?per_page=1000`)).map(rule => rule.precedence ?? 0)) + 1;
      await cf(policies, 'POST', { name: RELAY_DEVICES, decision: 'non_identity', include: withToken([], token.id), precedence });
    }
    await sql('INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES (?, ?, ?, ?, ?, ?)',
      randomUUID(), parsed.name, token.client_id, token.id, Date.now(), kind.reaches);
  } catch (error) {
    // A key Relay does not list opens nothing, but it should not linger in Cloudflare either.
    await cf(`${root}/access/service_tokens/${token.id}`, 'DELETE').catch(() => {});
    throw error;
  }
  const code = connectCode({ server, clientId: token.client_id, clientSecret: token.client_secret });
  mkdirSync(HAND_OVER, { recursive: true, mode: 0o700 });
  const page = join(HAND_OVER, `${slug(parsed.name)}-${Date.now()}.html`);
  const chats = kind.reaches === 'chats';
  writeFileSync(page, chats ? chatHandOverPage({ name: parsed.name, code })
    : handOverPage({ name: parsed.name, server, clientId: token.client_id, clientSecret: token.client_secret, qrSvg: qr(code, 'SVG') }), { mode: 0o600 });
  // The code reaches only a person's own terminal: an assistant's captured output never holds the secret. A chat key's
  // code is pasted on the same computer, so it shows as text, not as a QR code.
  const terminal = !process.stdout.isTTY ? null : chats ? `Connect code for Claude Code:\n${code}\n` : qr(code, 'UTF8');
  if (terminal) console.log(terminal);
  console.log(`Made the key "${parsed.name}" (expires in a year). Its private page, for you alone: ${page}`);
}

if (isMain(import.meta.url)) main().catch(error => {
  console.error(`relay-device-key: ${error.message}`);
  process.exitCode = 1;
});
