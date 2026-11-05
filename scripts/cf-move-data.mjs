#!/usr/bin/env node
// Moves D1 databases and R2 buckets to newly named ones inside the Cloudflare account, through a one-off Worker
// bound to both sides, then checks every row and file. wiki/stack/move-cloudflare-data.md
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { copyFileSync, existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { isMain, parseCli, usageError } from './lib-cli.mjs';
import { repoRoot } from './lib-wrangler-config.mjs';
import { primaryRoot } from '../.claude/skills/memory/scripts/lib/primary-root.mjs';

const USAGE = `usage: node scripts/cf-move-data.mjs [--d1 <old>=<new>]... [--r2 <old>=<new>]... [--replace] [--check-only] [--worker <name>]
  --d1 old=new    copy a D1 database's rows into a new database that already has the schema
  --r2 old=new    copy an R2 bucket's files into a new bucket
  --replace       also take rows changed since the last copy (columns a trigger guards stay)
  --check-only    copy nothing; only compare both sides
  --worker        the one-off Worker's name (default relay-everything-move); it is deleted at the end
Prints only names and counts, then result=passed or result=failed.`;

const NAME = /^[a-z0-9][a-z0-9-]{0,62}$/;

/** The pairs to move, or a usage problem. */
export function parseMove(args) {
  const { values } = parseCli({ usage: USAGE, args, options: {
    d1: { type: 'string', multiple: true, default: [] }, r2: { type: 'string', multiple: true, default: [] },
    replace: { type: 'boolean' }, 'check-only': { type: 'boolean' }, worker: { type: 'string', default: 'relay-everything-move' },
  } });
  const pairs = items => items.map(item => {
    const [from, to, extra] = item.split('=');
    return NAME.test(from ?? '') && NAME.test(to ?? '') && from !== to && extra === undefined ? { from, to } : null;
  });
  const d1 = pairs(values.d1);
  const r2 = pairs(values.r2);
  if ([...d1, ...r2].includes(null)) return { problem: '--d1 and --r2 take <old>=<new>, two different store names' };
  if (!d1.length && !r2.length) return { problem: 'name at least one --d1 or --r2 pair' };
  if (!NAME.test(values.worker)) return { problem: '--worker takes a Worker name' };
  return { d1, r2, replace: !!values.replace, checkOnly: !!values['check-only'], worker: values.worker };
}

/** A call to the move Worker: `send(init)` answers a Response; an error carries only the Worker's own words. */
export const caller = (send, key) => async body => {
  const response = await send({ method: 'POST', headers: { 'content-type': 'application/json', 'x-move-key': key }, body: JSON.stringify(body) });
  const answer = await response.json().catch(() => ({ error: `answered ${response.status}` }));
  if (!response.ok) throw new Error(`the move Worker refused ${body.op}: ${answer.error ?? response.status}`);
  return answer;
};

/** Calls `op` page by page until the Worker gives no cursor, and adds up each numeric field. */
async function pages(call, ask) {
  const sum = {};
  let cursor = null;
  do {
    const answer = await call({ ...ask, cursor });
    for (const [field, value] of Object.entries(answer)) if (typeof value === 'number') sum[field] = (sum[field] ?? 0) + value;
    cursor = answer.cursor ?? null;
  } while (cursor !== null);
  return sum;
}

const verdict = ok => (ok ? 'ok' : 'mismatch');

async function moveDatabase(call, pair, { from, to }, { replace, checkOnly, limit, print }) {
  print(`d1 ${from} -> ${to}`);
  const { tables, unsupported, absent = [] } = await call({ op: 'tables', pair });
  for (const name of unsupported) print(`table ${name} not copied: a virtual table with rows of its own mismatch`);
  for (const name of absent) print(`table ${name} not copied: the new side has no such table; apply its schema first mismatch`);
  if (!checkOnly) {
    // The new side's own AFTER triggers would write rows again that the copy already brings. An answer lost after
    // they went off still reaches the finally: `triggers-on` restores them from the list the new side saved.
    let triggers = [];
    try {
      ({ triggers } = await call({ op: 'triggers-off', pair }));
      for (const { name, links } of tables) {
        await pages(call, { op: 'copy', pair, table: name, replace, limit });
        if (links) await pages(call, { op: 'link', pair, table: name, replace, limit });
      }
    } finally {
      await call({ op: 'triggers-on', pair, triggers });
    }
  }
  let passed = unsupported.length === 0 && absent.length === 0;
  for (const { name } of tables) {
    const counts = await call({ op: 'count', pair, table: name });
    const { missing = 0, differ = 0 } = await pages(call, { op: 'check', pair, table: name, limit });
    const extra = Math.max(0, counts.new - (counts.old - missing));
    const ok = missing === 0 && differ === 0;
    passed &&= ok;
    print(`table ${name} old=${counts.old} new=${counts.new} missing=${missing} differ=${differ} extra=${extra} ${verdict(ok)}`);
  }
  const triggers = await call({ op: 'triggers', pair });
  passed &&= triggers.missing === 0;
  print(`triggers old=${triggers.old} new=${triggers.new} missing=${triggers.missing} ${verdict(triggers.missing === 0)}`);
  for (const index of (await call({ op: 'indexes', pair })).indexes) {
    passed &&= index.rows === index.source;
    print(`index ${index.name} rows=${index.rows} source=${index.source} ${verdict(index.rows === index.source)}`);
  }
  return passed;
}

async function moveBucket(call, pair, { from, to }, { checkOnly, limit, print }) {
  if (!checkOnly) await pages(call, { op: 'copy-bucket', pair, limit });
  const old = await pages(call, { op: 'check-bucket', pair, limit });
  const fresh = await pages(call, { op: 'size-bucket', pair, limit });
  const [files, bytes, missing, differ] = [old.old ?? 0, old.bytes ?? 0, old.missing ?? 0, old.differ ?? 0];
  const extra = Math.max(0, (fresh.files ?? 0) - (files - missing));
  const ok = missing === 0 && differ === 0;
  print(`bucket ${from} -> ${to} old=${files} new=${fresh.files ?? 0} bytes_old=${bytes} bytes_new=${fresh.bytes ?? 0} missing=${missing} differ=${differ} extra=${extra} ${verdict(ok)}`);
  return ok;
}

/** Copies (unless checkOnly) and checks each pair; prints names and counts and a result= line, and answers it. */
export async function move({ call, d1 = [], r2 = [], replace = false, checkOnly = false, limit = 100, print = console.log }) {
  const options = { replace, checkOnly, limit, print };
  let passed = true;
  for (const [pair, names] of d1.entries()) passed = (await moveDatabase(call, pair, names, options)) && passed;
  for (const [pair, names] of r2.entries()) passed = (await moveBucket(call, pair, names, options)) && passed;
  print(`result=${passed ? 'passed' : 'failed'}`);
  return passed;
}

/** The throwaway Worker's config: each old and new store bound by its pair's number. */
export function moveConfig({ worker, account, d1, r2, databaseIds }) {
  return {
    name: worker, main: 'worker.mjs', account_id: account, compatibility_date: '2026-07-28', workers_dev: true, preview_urls: false,
    d1_databases: d1.flatMap(({ from, to }, pair) => [
      { binding: `D1_OLD_${pair}`, database_name: from, database_id: databaseIds[from] },
      { binding: `D1_NEW_${pair}`, database_name: to, database_id: databaseIds[to] },
    ]),
    r2_buckets: r2.flatMap(({ from, to }, pair) => [{ binding: `R2_OLD_${pair}`, bucket_name: from }, { binding: `R2_NEW_${pair}`, bucket_name: to }]),
  };
}

function cloudflare(token, account) {
  return async path => {
    const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}${path}`, { headers: { Authorization: `Bearer ${token}` } });
    const answer = await response.json().catch(() => ({}));
    if (!response.ok || !answer.success) throw new Error(`Cloudflare GET ${path}: ${response.status} ${answer.errors?.map(error => error.message).join('; ') ?? ''}`);
    return answer.result;
  };
}

async function databaseId(cf, name) {
  const found = (await cf(`/d1/database?name=${encodeURIComponent(name)}&per_page=100`)).find(database => database.name === name);
  if (!found) throw new Error(`no D1 database named ${name}`);
  return found.uuid;
}

/** Waits for the new workers.dev address to answer with the key, about two minutes at most. */
async function ready(call) {
  for (let tries = 0; ; tries += 1) {
    try {
      return await call({ op: 'ping' });
    } catch (error) {
      if (tries >= 40) throw new Error(`the move Worker never answered: ${error.message}`);
      await new Promise(resolve => setTimeout(resolve, 3000));
    }
  }
}

async function main() {
  const parsed = parseMove(process.argv.slice(2));
  if (parsed.problem) usageError(USAGE, parsed.problem);
  const envFile = join(primaryRoot(repoRoot).primary, '.env');
  if (!process.env.CLOUDFLARE_API_TOKEN && existsSync(envFile)) process.loadEnvFile(envFile);
  const { CLOUDFLARE_API_TOKEN: token, CLOUDFLARE_ACCOUNT_ID: account } = process.env;
  if (!token || !/^[a-f0-9]{32}$/i.test(account ?? '')) throw new Error('CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID is missing from .env');
  const cf = cloudflare(token, account);
  const databaseIds = {};
  for (const name of parsed.d1.flatMap(({ from, to }) => [from, to])) databaseIds[name] = await databaseId(cf, name);

  // Outside the repository, and gone at the end: the config names stores, and the key lives only in memory.
  const work = mkdtempSync(join(tmpdir(), 'cf-move-'));
  const config = join(work, 'wrangler.json');
  const wrangler = (args, input) => {
    try {
      return execFileSync(join(repoRoot, 'app', 'node_modules', '.bin', 'wrangler'), [...args, '--config', config], { cwd: work, input,
        encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, CLOUDFLARE_API_TOKEN: token, CLOUDFLARE_ACCOUNT_ID: account } });
    } catch (error) {
      const said = String(error.stderr || error.stdout || error.message).split('\n').map(line => line.trim()).filter(Boolean);
      throw new Error(`wrangler ${args[0]} failed: ${said.find(line => /error/i.test(line)) ?? said.at(-1)}`);
    }
  };
  let deployed = false;
  let live = null;
  let inflight = Promise.resolve();
  let stopping = false;
  const paused = new Set();
  const cleanUp = () => {
    if (deployed) {
      try { wrangler(['delete', '--name', parsed.worker, '--force']); console.log(`deleted ${parsed.worker}`); } catch (error) {
        console.error(`could not delete ${parsed.worker}; delete it by hand: ${error.message}`);
      }
      deployed = false;
    }
    rmSync(work, { recursive: true, force: true });
  };
  // A stop mid-copy would leave the new side's AFTER triggers off: put them back, best effort, before the Worker goes.
  const stop = async () => {
    stopping = true;
    if (live) {
      const restore = inflight.catch(() => {}).then(() => Promise.allSettled([...paused].map(pair => live({ op: 'triggers-on', pair }))));
      await Promise.race([restore, new Promise(resolve => setTimeout(resolve, 20000).unref())]);
    }
    cleanUp();
    process.exit(130);
  };
  process.once('SIGINT', stop).once('SIGTERM', stop);
  try {
    copyFileSync(join(repoRoot, 'scripts', 'cf-move-data', 'worker.mjs'), join(work, 'worker.mjs'));
    writeFileSync(config, JSON.stringify(moveConfig({ ...parsed, account, databaseIds }), null, 2));
    const key = randomBytes(32).toString('hex');
    deployed = true;
    wrangler(['deploy']);
    wrangler(['secret', 'put', 'MOVE_KEY'], key);
    const { subdomain } = await cf('/workers/subdomain');
    const url = `https://${parsed.worker}.${subdomain}.workers.dev/`;
    live = caller(init => fetch(url, init), key);
    // Once stopped, the move sends nothing more: `stop` restores the paused pairs' triggers after the call in flight.
    const call = async body => {
      if (stopping) throw new Error('stopped');
      if (body.op === 'triggers-off') paused.add(body.pair);
      const answer = await (inflight = live(body));
      if (body.op === 'triggers-on') paused.delete(body.pair);
      return answer;
    };
    await ready(call);
    return await move({ call, ...parsed });
  } finally {
    if (!stopping) cleanUp();
  }
}

if (isMain(import.meta.url)) {
  main().then(passed => { process.exitCode = passed ? 0 : 1; }, error => {
    console.log(`result=failed ${String(error.message).split('\n')[0]}`);
    process.exitCode = 1;
  });
}
