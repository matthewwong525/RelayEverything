#!/usr/bin/env node
// The one-time move of the owner's old Relay Everything data from D1 into their own space. It writes an hour's ticket
// to the directory, has the server move each table a page at a time, then compares counts. Safe to run again.
import { createHash, randomBytes } from 'node:crypto';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { isMain, parseCli, usageError } from './lib-cli.mjs';
import { cloudflare } from './relay-mcp-setup.mjs';
import { parseConfig, repoRoot } from './lib-wrangler-config.mjs';

const USAGE = `usage: node scripts/relay-move-to-space.mjs [--staging] [--self-host <config>] [--server <url>]
  (no flag)              move the live server's old data into the owner's space, at https://app.relayeverything.com
  --staging              the previews' server, https://app-staging.relayeverything.com
  --self-host <config>   your own server's self-host/wrangler.jsonc; give --server too
  --server <url>         the server's https:// address, with no path`;

/** The tables the move writes, in the order of app/worker/apps/relay/space.ts's MOVED: webhooks come last. */
export const MOVED = ['relay_devices', 'relay_notes', 'relay_health', 'relay_locations', 'relay_chats', 'relay_chat_messages',
  'relay_chat_saves', 'relay_webhooks'];
export const SERVERS = { production: 'https://app.relayeverything.com', staging: 'https://app-staging.relayeverything.com' };
const HOUR = 60 * 60_000;

export function parseCommand(args) {
  const { values } = parseCli({ usage: USAGE, args, options: { staging: { type: 'boolean' }, 'self-host': { type: 'string' }, server: { type: 'string' } } });
  if (values.server !== undefined && !/^https:\/\/[^/\s]+$/.test(values.server)) return { problem: '--server takes an https:// address with no path' };
  if (values.staging && values['self-host']) return { problem: 'your own server has no previews; leave out --staging' };
  if (values['self-host'] && !values.server) return { problem: '--self-host needs --server, your server\'s address' };
  return { staging: !!values.staging, selfHost: values['self-host'], server: values.server };
}

/** Where the move goes: the server's address, and the D1 database and account that hold its directory. */
export function target({ staging, selfHost, server }, config, env = {}) {
  const scope = staging ? config.env?.staging : config;
  const database = scope?.d1_databases?.find(entry => entry.binding === 'DB')?.database_id;
  const account = config.account_id ?? env.CLOUDFLARE_ACCOUNT_ID;
  if (!database || !/^[a-f0-9]{32}$/i.test(account ?? '')) throw new Error('the database or the account id is missing from the config');
  return { server: server ?? SERVERS[staging ? 'staging' : 'production'], database, account, selfHost: !!selfHost };
}

/** The result lines from the two counts: `result=ok`, or one `result=mismatch` line per table the space holds fewer
 *  rows of. The old tables stay as they were, while the space grows from use, so more is fine. */
export function compare({ old, space }) {
  const wrong = MOVED.filter(table => !(space[table] >= old[table]));
  return wrong.length ? wrong.map(table => `result=mismatch table=${table} old=${old[table]} space=${space[table]}`) : ['result=ok'];
}

/** One move. Cloudflare's API and the server come in through `request`, so a test stands in for both. */
export async function moveToSpace({ cf, account, database, server, request = fetch, log = console.log }) {
  const sql = async (query, ...params) => (await cf(`/accounts/${account}/d1/database/${database}/query`, 'POST', { sql: query, params }))[0].results;
  const ticket = randomBytes(32).toString('base64url');
  const fingerprint = createHash('sha256').update(ticket).digest('hex');
  await sql('INSERT INTO relay_move_tickets (token_sha256, expires_at) VALUES (?, ?)', fingerprint, Date.now() + HOUR);
  const ask = async body => {
    const response = await request(`${server}/apps/relay/move`, { method: 'POST',
      headers: { Authorization: `Bearer ${ticket}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    const answer = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(`the server answered ${response.status}: ${answer.error?.message ?? 'no reason'}`);
    return answer;
  };
  try {
    for (const table of MOVED) {
      const total = { read: 0, added: 0, missingFiles: 0 };
      for (let after = 0; after !== null;) {
        const page = await ask({ table, after });
        for (const part of Object.keys(total)) total[part] += page[part];
        after = page.next;
      }
      log(`moved table=${table} read=${total.read} added=${total.added}${total.missingFiles ? ` missing_recordings=${total.missingFiles}` : ''}`);
    }
    const lines = compare(await ask({ counts: true }));
    for (const line of lines) log(line);
    return lines[0] === 'result=ok' ? 'ok' : 'mismatch';
  } finally {
    await sql('DELETE FROM relay_move_tickets WHERE token_sha256 = ?', fingerprint).catch(() => {});
  }
}

async function main() {
  const parsed = parseCommand(process.argv.slice(2));
  if (parsed.problem) usageError(USAGE, parsed.problem);
  const envFile = join(repoRoot, parsed.selfHost ? 'self-host' : '', '.env');
  if (!process.env.CLOUDFLARE_API_TOKEN && existsSync(envFile)) process.loadEnvFile(envFile);
  try {
    if (!process.env.CLOUDFLARE_API_TOKEN) throw new Error('CLOUDFLARE_API_TOKEN is missing from .env');
    const config = parseConfig(parsed.selfHost ?? join(repoRoot, 'app', 'wrangler.jsonc'));
    const where = target(parsed, config, process.env);
    const result = await moveToSpace({ ...where, cf: cloudflare(process.env.CLOUDFLARE_API_TOKEN, fetch) });
    if (result !== 'ok') process.exitCode = 1;
  } catch (error) {
    console.log(`result=failed reason=${error.message}`);
    process.exitCode = 1;
  }
}

if (isMain(import.meta.url)) main();
