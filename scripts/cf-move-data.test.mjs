// Run with: node --test scripts/cf-move-data.test.mjs
// The move Worker runs in Miniflare against two local D1 databases and two local R2 buckets.
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { join } from 'node:path';
import { caller, move, moveConfig, parseMove } from './cf-move-data.mjs';
import { miniflare } from './lib-miniflare.mjs';
import { repoRoot } from './lib-wrangler-config.mjs';

const KEY = 'k'.repeat(64);
// Private words seeded into rows, keys and files: no line the move prints may hold them.
const MARKER = 'MARKER-health-7f3a';
const SCHEMA = [
  'CREATE TABLE notes (id TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices (id), body TEXT, audio BLOB)',
  'CREATE TABLE devices (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
  'CREATE TABLE stays (place TEXT NOT NULL, day TEXT NOT NULL, minutes INTEGER, PRIMARY KEY (place, day)) WITHOUT ROWID',
  'CREATE TABLE plain (label TEXT)',
  `CREATE TABLE facts (id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT NOT NULL, owner TEXT,
    superseded_by INTEGER REFERENCES facts (id))`,
  "CREATE TRIGGER facts_never_edited BEFORE UPDATE OF body ON facts BEGIN SELECT RAISE(ABORT, 'facts are never edited'); END",
  "CREATE TRIGGER facts_never_deleted BEFORE DELETE ON facts BEGIN SELECT RAISE(ABORT, 'facts are never deleted'); END",
  "CREATE VIRTUAL TABLE facts_fts USING fts5 (body, content = 'facts', content_rowid = 'id')",
  'CREATE TRIGGER facts_fts_insert AFTER INSERT ON facts BEGIN INSERT INTO facts_fts (rowid, body) VALUES (new.id, new.body); END',
  // An outbox a trigger fills: the copy brings the old side's rows, and the new side's trigger must not add more.
  'CREATE TABLE device_log (id INTEGER PRIMARY KEY AUTOINCREMENT, device TEXT NOT NULL)',
  'CREATE TRIGGER devices_logged AFTER INSERT ON devices BEGIN INSERT INTO device_log (device) VALUES (new.id); END',
  'CREATE TABLE d1_migrations (id INTEGER PRIMARY KEY, name TEXT, applied_at TEXT)',
];
const NAMES = { d1: [{ from: 'relay-ring-db', to: 'relay-everything-db' }], r2: [{ from: 'relay-ring-notes', to: 'relay-everything-notes' }] };

let mf;
let oldDb;
let newDb;
let oldBucket;
let newBucket;
let call;
const printed = [];

const run = async (flags = {}) => {
  const lines = [];
  const passed = await move({ call, ...NAMES, limit: 2, print: line => lines.push(line), ...flags });
  printed.push(...lines);
  return { passed, lines, line: prefix => lines.find(line => line.startsWith(prefix)) };
};
const exec = (db, ...sql) => db.batch(sql.map(statement => db.prepare(statement)));
const rows = async (db, table) => (await db.prepare(`SELECT * FROM ${table} ORDER BY 1`).all()).results;

before(async () => {
  const start = await miniflare();
  mf = start({
    modules: true, scriptPath: join(repoRoot, 'scripts', 'cf-move-data', 'worker.mjs'), compatibilityDate: '2026-07-28',
    bindings: { MOVE_KEY: KEY },
    d1Databases: { D1_OLD_0: 'old-db', D1_NEW_0: 'new-db' }, r2Buckets: { R2_OLD_0: 'old-bucket', R2_NEW_0: 'new-bucket' },
  });
  [oldDb, newDb, oldBucket, newBucket] = await Promise.all([mf.getD1Database('D1_OLD_0'), mf.getD1Database('D1_NEW_0'),
    mf.getR2Bucket('R2_OLD_0'), mf.getR2Bucket('R2_NEW_0')]);
  call = caller(init => mf.dispatchFetch('http://move.example/', init), KEY);
  await exec(oldDb, ...SCHEMA);
  await exec(newDb, ...SCHEMA);
  await exec(oldDb,
    `INSERT INTO devices VALUES ('d1', 'Phone ${MARKER}'), ('d2', 'Pebble')`,
    `INSERT INTO notes VALUES ('n1', 'd1', 'walked ${MARKER}', x'00ff10'), ('n2', 'd2', 'slept', NULL), ('n3', 'd1', 'ran', NULL)`,
    `INSERT INTO stays VALUES ('home ${MARKER}', '2026-11-04', 600), ('work', '2026-11-04', 480), ('gym', '2026-11-05', 60)`,
    `INSERT INTO plain VALUES ('${MARKER}'), ('two'), ('two')`,
    // Fact 1 names fact 2, which comes after it: the copy puts the link in once fact 2 is there.
    `INSERT INTO facts (id, body) VALUES (2, 'second ${MARKER}')`,
    `INSERT INTO facts (id, body, superseded_by) VALUES (1, 'first ${MARKER}', 2)`,
    "INSERT INTO d1_migrations VALUES (1, '0001.sql', 'then')");
  await exec(newDb, "INSERT INTO d1_migrations VALUES (1, '0001.sql', 'now')");
  await oldBucket.put(`notes/${MARKER}.m4a`, `audio ${MARKER}`, { httpMetadata: { contentType: 'audio/mp4' }, customMetadata: { device: MARKER } });
  await oldBucket.put('notes/b.m4a', 'more audio');
  await oldBucket.put('notes/c.m4a', 'still more audio');
});
after(() => mf?.dispose());

test('a request without the key, or with another, is refused', async () => {
  for (const headers of [{}, { 'x-move-key': 'x'.repeat(64) }]) {
    const answer = await mf.dispatchFetch('http://move.example/', { method: 'POST', headers, body: '{"op":"tables","pair":0}' });
    assert.equal(answer.status, 403);
  }
  await assert.rejects(caller(init => mf.dispatchFetch('http://move.example/', init), 'x'.repeat(64))({ op: 'ping' }), /refused/);
});

test('the first copy moves every row and file, the index fills, and the check passes', async () => {
  const { passed, lines, line } = await run();
  assert.ok(passed, lines.join('\n'));
  assert.equal(lines.at(-1), 'result=passed');
  assert.deepEqual(lines.filter(text => text.startsWith('table ')).map(text => text.split(' ')[1]),
    ['devices', 'notes', 'stays', 'plain', 'facts', 'device_log'], 'parents before the rows that name them; the ledger skipped');
  assert.equal(line('table device_log'), 'table device_log old=2 new=2 missing=0 differ=0 extra=0 ok');
  assert.equal(line('triggers'), 'triggers old=4 new=4 missing=0 ok');
  assert.equal(line('table notes'), 'table notes old=3 new=3 missing=0 differ=0 extra=0 ok');
  assert.equal(line('index facts_fts'), 'index facts_fts rows=2 source=2 ok');
  assert.equal(line('bucket'), 'bucket relay-ring-notes -> relay-everything-notes old=3 new=3 bytes_old=50 bytes_new=50 missing=0 differ=0 extra=0 ok');
  for (const table of ['devices', 'notes', 'stays', 'plain', 'facts', 'device_log']) assert.deepEqual(await rows(newDb, table), await rows(oldDb, table), table);
  const copied = await newBucket.get(`notes/${MARKER}.m4a`);
  assert.equal(await copied.text(), `audio ${MARKER}`);
  assert.equal(copied.httpMetadata.contentType, 'audio/mp4');
  assert.deepEqual(copied.customMetadata, { device: MARKER });
  assert.equal((await newDb.prepare("SELECT rowid FROM facts_fts WHERE facts_fts MATCH 'second'").all()).results.length, 1);
});

test('a second run doubles nothing', async () => {
  const { passed, line } = await run();
  assert.ok(passed);
  assert.equal(line('table plain'), 'table plain old=3 new=3 missing=0 differ=0 extra=0 ok');
  assert.match(line('bucket'), / old=3 new=3 /);
});

test('a row kept after the first copy arrives once; a newer row on the new side passes as extra', async () => {
  await exec(oldDb, "INSERT INTO notes VALUES ('n4', 'd2', 'swam', NULL)", "INSERT INTO devices VALUES ('d3', 'Watch')");
  await exec(newDb, "INSERT INTO notes VALUES ('n9', 'd1', 'kept at the new address', NULL)");
  const { passed, line } = await run();
  assert.ok(passed);
  assert.equal(line('table notes'), 'table notes old=4 new=5 missing=0 differ=0 extra=1 ok');
  assert.equal((await newDb.prepare("SELECT count(*) AS n FROM notes WHERE id = 'n4'").first()).n, 1);
});

test('an edited row fails the check without --replace, and --replace takes it, links too', async () => {
  await exec(oldDb, "UPDATE notes SET body = 'walked far' WHERE id = 'n1'", "UPDATE stays SET minutes = 30 WHERE place = 'gym'",
    "INSERT INTO facts (id, body) VALUES (3, 'third')", 'UPDATE facts SET superseded_by = 3 WHERE id = 2');
  const plain = await run();
  assert.equal(plain.passed, false);
  assert.equal(plain.line('table notes'), 'table notes old=4 new=5 missing=0 differ=1 extra=1 mismatch');
  assert.match(plain.line('table stays'), /differ=1 .*mismatch$/);
  assert.equal(plain.lines.at(-1), 'result=failed');
  const replaced = await run({ replace: true });
  assert.ok(replaced.passed, replaced.lines.join('\n'));
  assert.equal((await newDb.prepare("SELECT body FROM notes WHERE id = 'n1'").first()).body, 'walked far');
  assert.equal((await newDb.prepare('SELECT minutes FROM stays WHERE place = \'gym\'').first()).minutes, 30);
  assert.equal((await newDb.prepare('SELECT superseded_by FROM facts WHERE id = 2').first()).superseded_by, 3);
});

test('a missing file fails the check, naming the bucket and both counts; the next copy brings it back', async () => {
  await newBucket.delete('notes/b.m4a');
  const checked = await run({ checkOnly: true });
  assert.equal(checked.passed, false);
  assert.equal(checked.line('bucket'),
    'bucket relay-ring-notes -> relay-everything-notes old=3 new=2 bytes_old=50 bytes_new=40 missing=1 differ=0 extra=0 mismatch');
  assert.equal(await newBucket.head('notes/b.m4a'), null, '--check-only copies nothing');
  assert.ok((await run()).passed);
});

test('a guarded table is never replaced: a fact with the same id and other words fails as differ', async () => {
  await exec(oldDb, "INSERT INTO facts (id, body) VALUES (10, 'saved at the old address')");
  await exec(newDb, "INSERT INTO facts (id, body) VALUES (10, 'saved at the new address')");
  const { passed, line } = await run({ replace: true });
  assert.equal(passed, false);
  assert.equal(line('table facts'), 'table facts old=4 new=4 missing=0 differ=1 extra=0 mismatch');
  assert.equal((await newDb.prepare('SELECT body FROM facts WHERE id = 10').first()).body, 'saved at the new address');
});

test('a trigger missing on the new side fails the check by count, and the copy never adds an old trigger', async () => {
  const { triggers } = await call({ op: 'triggers-off', pair: 0 });
  const stopped = await run();
  assert.equal(stopped.line('triggers'), 'triggers old=4 new=2 missing=2 mismatch');
  assert.equal(stopped.passed, false);
  await call({ op: 'triggers-on', pair: 0, triggers });
  assert.equal((await run({ checkOnly: true })).line('triggers'), 'triggers old=4 new=4 missing=0 ok');
  await exec(newDb, "INSERT INTO devices VALUES ('d9', 'Kept at the new address')");
  assert.equal((await newDb.prepare("SELECT count(*) AS n FROM device_log WHERE device = 'd9'").first()).n, 1);
  await exec(newDb, "DELETE FROM device_log WHERE device = 'd9'", "DELETE FROM devices WHERE id = 'd9'");
});

test('an old table the new side lacks fails up front, by name, and the other tables still copy', async () => {
  await exec(oldDb, 'CREATE TABLE outbox (id TEXT PRIMARY KEY)', "INSERT INTO outbox VALUES ('o1')", "INSERT INTO devices VALUES ('d4', 'Tablet')");
  const { passed, line } = await run();
  assert.equal(passed, false);
  assert.equal(line('table outbox'), 'table outbox not copied: the new side has no such table; apply its schema first mismatch');
  assert.match(line('table devices'), /old=4 new=4 .* ok$/);
  await exec(oldDb, 'DROP TABLE outbox');
});

test('nothing the move printed holds a row, a key or a file', () => {
  assert.ok(printed.length > 20);
  for (const line of printed) assert.ok(!line.includes(MARKER) && !line.includes('walked') && !line.includes('audio'), line);
});

test('the command line takes old=new pairs, and the config binds each side by its pair number', () => {
  assert.deepEqual(parseMove(['--d1', 'a-db=b-db', '--r2', 'a-notes=b-notes', '--replace']),
    { d1: [{ from: 'a-db', to: 'b-db' }], r2: [{ from: 'a-notes', to: 'b-notes' }], replace: true, checkOnly: false, worker: 'relay-everything-move' });
  for (const args of [[], ['--d1', 'a-db'], ['--d1', 'a=a'], ['--r2', 'a=b=c'], ['--d1', 'A_db=b'], ['--d1', 'a=b', '--worker', 'Bad Name']]) {
    assert.ok(parseMove(args).problem, JSON.stringify(args));
  }
  const config = moveConfig({ worker: 'w', account: 'acct', d1: [{ from: 'a', to: 'b' }], r2: [{ from: 'c', to: 'd' }], databaseIds: { a: 'id-a', b: 'id-b' } });
  assert.deepEqual(config.d1_databases.map(binding => [binding.binding, binding.database_id]), [['D1_OLD_0', 'id-a'], ['D1_NEW_0', 'id-b']]);
  assert.deepEqual(config.r2_buckets, [{ binding: 'R2_OLD_0', bucket_name: 'c' }, { binding: 'R2_NEW_0', bucket_name: 'd' }]);
  assert.equal(config.workers_dev, true);
  assert.equal('routes' in config, false);
});
