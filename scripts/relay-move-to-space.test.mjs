// Run with: node --test scripts/relay-move-to-space.test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { repoRoot } from './lib-wrangler-config.mjs';
import { compare, MOVED, moveToSpace, parseCommand, SERVERS, target } from './relay-move-to-space.mjs';

const ACCOUNT = 'a'.repeat(32);
const counts = value => Object.fromEntries(MOVED.map(table => [table, value]));

test('the moved tables match the server\'s list, in its order', () => {
  const source = readFileSync(join(repoRoot, 'app', 'worker', 'apps', 'relay', 'space.ts'), 'utf8');
  const listed = /export const MOVED = \[([^\]]+)\]/.exec(source)[1].match(/"([a-z_]+)"/g).map(name => name.slice(1, -1));
  assert.deepEqual(MOVED, listed);
});

test('the flags pick the server, and refuse a bad address or a self-host with previews', () => {
  assert.deepEqual(parseCommand([]), { staging: false, selfHost: undefined, server: undefined });
  assert.equal(parseCommand(['--staging']).staging, true);
  assert.match(parseCommand(['--server', 'http://relay.example.com']).problem, /https/);
  assert.match(parseCommand(['--self-host', 'x.jsonc', '--staging', '--server', 'https://a.example.com']).problem, /no previews/);
  assert.match(parseCommand(['--self-host', 'x.jsonc']).problem, /--server/);
});

test('each place moves into its own database, at its own address', () => {
  const config = { account_id: ACCOUNT, d1_databases: [{ binding: 'DB', database_id: 'live' }], env: { staging: { d1_databases: [{ binding: 'DB', database_id: 'stage' }] } } };
  assert.deepEqual(target({ staging: false }, config), { server: SERVERS.production, database: 'live', account: ACCOUNT, selfHost: false });
  assert.deepEqual(target({ staging: true }, config), { server: SERVERS.staging, database: 'stage', account: ACCOUNT, selfHost: false });
  assert.equal(target({ selfHost: 'c', server: 'https://relay.you.workers.dev' }, { d1_databases: config.d1_databases }, { CLOUDFLARE_ACCOUNT_ID: ACCOUNT }).server,
    'https://relay.you.workers.dev');
  assert.throws(() => target({}, { d1_databases: [] }), /database or the account/);
});

test('the counts give ok, or one mismatch line per table', () => {
  assert.deepEqual(compare({ old: counts(3), space: counts(3) }), ['result=ok']);
  assert.deepEqual(compare({ old: counts(3), space: { ...counts(3), relay_notes: 2 } }), ['result=mismatch table=relay_notes old=3 space=2']);
});

test('a space that grew after the first move still gives ok, so a second run passes', () => {
  assert.deepEqual(compare({ old: counts(3), space: { ...counts(3), relay_notes: 40, relay_health: 900 } }), ['result=ok']);
  assert.deepEqual(compare({ old: counts(3), space: { ...counts(9), relay_chats: undefined } }), ['result=mismatch table=relay_chats old=3 space=undefined']);
});

/** Cloudflare's D1 API and the server, as one fetch: `pages` answers each table's pages in order. */
function fakes({ pages = {}, space = counts(0), status = 200 } = {}) {
  const sql = [];
  const asked = [];
  const request = async (url, init) => {
    const body = JSON.parse(init.body);
    if (url.startsWith('https://api.cloudflare.com/')) {
      sql.push(body);
      return Response.json({ success: true, result: [{ results: [] }] });
    }
    asked.push({ url, body, auth: init.headers.Authorization });
    if (status !== 200) return Response.json({ error: { message: 'This move ticket is wrong or has expired.' } }, { status });
    if (body.counts) return Response.json({ old: counts(0), space });
    const page = (pages[body.table] ?? [{ read: 0, added: 0, missingFiles: 0, next: null }]).find(item => item.after === body.after) ??
      { read: 0, added: 0, missingFiles: 0, next: null };
    return Response.json({ table: body.table, ...page });
  };
  const cf = async (path, method, body) => {
    const response = await request(`https://api.cloudflare.com/client/v4${path}`, { method, body: JSON.stringify(body) });
    return (await response.json()).result;
  };
  return { request, cf, sql, asked };
}

test('a move writes a ticket, follows each table\'s pages, checks the counts and deletes the ticket', async () => {
  const pages = { relay_notes: [{ after: 0, read: 200, added: 200, missingFiles: 1, next: 200 }, { after: 200, read: 5, added: 5, missingFiles: 0, next: null }] };
  const { request, cf, sql, asked } = fakes({ pages });
  const lines = [];
  const result = await moveToSpace({ cf, account: ACCOUNT, database: 'db', server: 'https://relay.example.com', request, log: line => lines.push(line) });
  assert.equal(result, 'ok');
  assert.match(sql[0].sql, /INSERT INTO relay_move_tickets/);
  assert.ok(sql[0].params[1] > Date.now() + 59 * 60_000);
  assert.match(sql.at(-1).sql, /DELETE FROM relay_move_tickets/);
  assert.equal(sql.at(-1).params[0], sql[0].params[0]);
  assert.ok(asked.every(item => item.url === 'https://relay.example.com/apps/relay/move' && /^Bearer \S{43}$/.test(item.auth)));
  // The server gets the ticket; the directory keeps only its fingerprint.
  assert.notEqual(asked[0].auth.slice(7), sql[0].params[0]);
  assert.deepEqual(asked.filter(item => item.body.table === 'relay_notes').map(item => item.body.after), [0, 200]);
  assert.ok(lines.includes('moved table=relay_notes read=205 added=205 missing_recordings=1'));
  assert.ok(lines.includes('moved table=relay_webhooks read=0 added=0'));
  assert.equal(lines.at(-1), 'result=ok');
});

test('a count that differs gives mismatch, and a refused ticket still deletes the ticket', async () => {
  const short = fakes({ space: { ...counts(0), relay_health: -1 } });
  const lines = [];
  assert.equal(await moveToSpace({ ...short, account: ACCOUNT, database: 'db', server: 'https://r.example.com', log: line => lines.push(line) }), 'mismatch');
  assert.equal(lines.at(-1), 'result=mismatch table=relay_health old=0 space=-1');
  const refused = fakes({ status: 403 });
  await assert.rejects(moveToSpace({ ...refused, account: ACCOUNT, database: 'db', server: 'https://r.example.com', log: () => {} }), /403: This move ticket/);
  assert.match(refused.sql.at(-1).sql, /DELETE FROM relay_move_tickets/);
});
