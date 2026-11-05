// The one-off Worker that copies D1 databases and R2 buckets to new ones inside the account, answering only names
// and counts. scripts/cf-move-data.mjs deploys, calls and deletes it: wiki/stack/move-cloudflare-data.md

// Migration ledgers belong to the new side's own schema step, which already wrote them; the paused-trigger list is the
// move's own.
const PAUSED = '_move_paused_triggers';
const SKIPPED = /^(sqlite_|_cf_)|^(d1_migrations|schema_migrations|_move_paused_triggers)$/i;
const FTS_SHADOW = ['data', 'idx', 'content', 'docsize', 'config'];
const quote = name => `"${String(name).replaceAll('"', '""')}"`;
const list = names => names.map(quote).join(', ');

/** A blob comes back as bytes; a JSON number and its string differ. */
function norm(value) {
  const bytes = Array.isArray(value) || value instanceof ArrayBuffer ? new Uint8Array(value)
    : ArrayBuffer.isView(value) ? new Uint8Array(value.buffer, value.byteOffset, value.byteLength) : null;
  if (bytes) return `b:${[...bytes].map(byte => byte.toString(16).padStart(2, '0')).join('')}`;
  return JSON.stringify(value ?? null);
}
const bindable = value => (Array.isArray(value) ? new Uint8Array(value) : value);

/** The columns named by `BEFORE UPDATE OF` triggers, and whether a trigger guards every column. */
function guards(triggers) {
  const columns = new Set();
  let wholeRow = false;
  for (const sql of triggers) {
    const match = /\bBEFORE\s+UPDATE\b(?:\s+OF\s+([\s\S]+?))?\s+ON\s/i.exec(sql ?? '');
    if (!match) continue;
    if (match[1]) for (const name of match[1].split(',')) columns.add(name.trim().replace(/^["`[]|["`\]]$/g, ''));
    // A row-wide guard with a WHEN refuses only what the old side refused too; one with none refuses every edit.
    else if (!/\bWHEN\b/i.test(sql.slice(0, sql.search(/\bBEGIN\b/i)))) wholeRow = true;
  }
  return { columns, wholeRow };
}

async function tableInfo(db, table) {
  const columns = (await db.prepare(`PRAGMA table_info(${quote(table)})`).all()).results;
  const found = await db.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?").bind(table).first();
  if (!found) throw new Error(`no table ${String(table).slice(0, 60)} on the old side`);
  const { sql } = found;
  const triggers = (await db.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name = ?").bind(table).all()).results;
  const foreign = (await db.prepare(`PRAGMA foreign_key_list(${quote(table)})`).all()).results;
  const names = columns.map(column => column.name);
  const pk = columns.filter(column => column.pk > 0).sort((a, b) => a.pk - b.pk).map(column => column.name);
  const withoutRowid = /WITHOUT\s+ROWID/i.test(sql.slice(sql.lastIndexOf(')')));
  // A link to a row of the same table goes in after the whole table, so a row may name a later one.
  const links = foreign.filter(key => key.table === table).map(key => key.from)
    .filter(name => !pk.includes(name) && !columns.find(column => column.name === name).notnull);
  return { table, names, pk, withoutRowid, links, guard: guards(triggers.map(trigger => trigger.sql)) };
}

/** One page of the old table, by rowid, or by offset in primary-key order for a table with no rowid. */
async function page(db, info, cursor, limit, where = '') {
  const filter = where ? ` AND (${where})` : '';
  if (info.withoutRowid) {
    const offset = cursor ?? 0;
    const rows = (await db.prepare(`SELECT * FROM ${quote(info.table)} WHERE 1${filter} ORDER BY ${list(info.pk)} LIMIT ? OFFSET ?`)
      .bind(limit, offset).all()).results;
    return { rows, next: rows.length < limit ? null : offset + rows.length };
  }
  const after = cursor === undefined || cursor === null ? '1' : 'rowid > ?';
  const rows = (await db.prepare(`SELECT rowid AS __move_rowid, * FROM ${quote(info.table)} WHERE ${after}${filter} ORDER BY rowid LIMIT ?`)
    .bind(...(after === '1' ? [] : [cursor]), limit).all()).results;
  return { rows, next: rows.length < limit ? null : rows.at(-1).__move_rowid };
}

/** A row is matched by its primary key, or by rowid when the table declares none. */
const keyOf = info => (info.pk.length ? info.pk : ['rowid']);
const keyValues = (info, row) => (info.pk.length ? info.pk.map(name => row[name]) : [row.__move_rowid]);
const keyMatch = info => keyOf(info).map(name => `${name === 'rowid' ? 'rowid' : quote(name)} IS ?`).join(' AND ');

function insertSql(info, replace) {
  const names = info.pk.length || info.withoutRowid ? info.names : ['rowid', ...info.names];
  const columns = `${quote(info.table)} (${names.map(name => (name === 'rowid' ? 'rowid' : quote(name))).join(', ')}) VALUES (${names.map(() => '?').join(', ')})`;
  const guarded = info.guard.wholeRow || info.guard.columns.size;
  if (!replace || (!info.pk.length && guarded)) return { names, sql: `INSERT OR IGNORE INTO ${columns}` };
  if (!info.pk.length) return { names, sql: `INSERT OR REPLACE INTO ${columns}` };
  // An update, not REPLACE: REPLACE deletes the row first, which delete guards and foreign keys refuse.
  const editable = info.guard.wholeRow ? [] : info.names.filter(name => !info.pk.includes(name) && !info.guard.columns.has(name) && !info.links.includes(name));
  if (!editable.length) return { names, sql: `INSERT OR IGNORE INTO ${columns}` };
  const set = editable.map(name => `${quote(name)} = excluded.${quote(name)}`).join(', ');
  const changed = editable.map(name => `${quote(name)} IS NOT excluded.${quote(name)}`).join(' OR ');
  return { names, sql: `INSERT INTO ${columns} ON CONFLICT (${list(info.pk)}) DO UPDATE SET ${set} WHERE ${changed}` };
}

async function copyPage(from, to, info, { cursor, replace, limit }) {
  const { rows, next } = await page(from, info, cursor, limit);
  const { names, sql } = insertSql(info, replace);
  const statement = to.prepare(sql);
  const values = row => names.map(name => (name === 'rowid' ? row.__move_rowid : info.links.includes(name) ? null : bindable(row[name])));
  if (rows.length) await to.batch(rows.map(row => statement.bind(...values(row))));
  return { rows: rows.length, cursor: next };
}

/** Puts each same-table link back once the rows it names are there: fills an empty one, or with replace, any. */
async function linkPage(from, to, info, { cursor, replace, limit }) {
  const { rows, next } = await page(from, info, cursor, limit, info.links.map(name => `${quote(name)} IS NOT NULL`).join(' OR '));
  const statements = rows.flatMap(row => info.links.filter(name => row[name] !== null).map(name => to
    .prepare(`UPDATE ${quote(info.table)} SET ${quote(name)} = ? WHERE ${keyMatch(info)} AND ${quote(name)} ${replace ? 'IS NOT ?' : 'IS NULL'}`)
    .bind(row[name], ...keyValues(info, row), ...(replace ? [row[name]] : []))));
  if (statements.length) await to.batch(statements);
  return { rows: rows.length, cursor: next };
}

async function checkPage(from, to, info, { cursor, limit }) {
  const { rows, next } = await page(from, info, cursor, limit);
  const lookup = to.prepare(`SELECT ${list(info.names)} FROM ${quote(info.table)} WHERE ${keyMatch(info)}`);
  const found = rows.length ? await to.batch(rows.map(row => lookup.bind(...keyValues(info, row).map(bindable)))) : [];
  let missing = 0;
  let differ = 0;
  rows.forEach((row, index) => {
    const twin = found[index].results[0];
    if (!twin) missing += 1;
    else if (info.names.some(name => norm(row[name]) !== norm(twin[name]))) differ += 1;
  });
  return { old: rows.length, missing, differ, cursor: next };
}

const count = async (db, table) => (await db.prepare(`SELECT count(*) AS n FROM ${quote(table)}`).first()).n;

/** The tables to copy, each after the tables its rows name; the virtual tables this tool can't copy; and the old
 *  tables the new side lacks, which need their schema first. */
async function tables(db, fresh) {
  const all = (await db.prepare("SELECT name, sql FROM sqlite_master WHERE type = 'table'").all()).results;
  const virtual = all.filter(table => /^\s*CREATE\s+VIRTUAL\s+TABLE/i.test(table.sql ?? ''));
  const shadow = new Set(virtual.flatMap(table => FTS_SHADOW.map(suffix => `${table.name}_${suffix}`)));
  const plain = all.filter(table => !virtual.includes(table) && !shadow.has(table.name) && !SKIPPED.test(table.name)).map(table => table.name);
  const after = new Map();
  for (const name of plain) {
    const foreign = (await db.prepare(`PRAGMA foreign_key_list(${quote(name)})`).all()).results;
    after.set(name, foreign.map(key => key.table).filter(other => other !== name && plain.includes(other)));
  }
  const ordered = [];
  const visit = (name, path) => {
    if (ordered.includes(name) || path.includes(name)) return;
    for (const other of after.get(name)) visit(other, [...path, name]);
    ordered.push(name);
  };
  for (const name of plain) visit(name, []);
  const unsupported = virtual.filter(table => !externalContent(table.sql)).map(table => table.name);
  const present = new Set((await fresh.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all()).results.map(table => table.name));
  const absent = ordered.filter(name => !present.has(name));
  const withLinks = await Promise.all(ordered.filter(name => present.has(name))
    .map(async name => ({ name, links: (await tableInfo(db, name)).links.length > 0 })));
  return { tables: withLinks, unsupported, absent };
}

/** An FTS5 index over another table's rows: rebuilt on the new side after the copy, so it is checked, not copied. */
const externalContent = sql => /USING\s+fts5\s*\(/i.test(sql ?? '') && /\bcontent\s*=\s*'?[A-Za-z_]/i.test(sql);

const triggerList = async db => (await db.prepare("SELECT name, sql FROM sqlite_master WHERE type = 'trigger'").all()).results;
// An AFTER trigger writes rows of its own, such as an outbox or a search index: the copy brings those rows already.
const writes = sql => /^\s*CREATE\s+TRIGGER\s+(?:IF\s+NOT\s+EXISTS\s+)?\S+\s+AFTER\b/i.test(sql ?? '');

/** Saves the new side's AFTER triggers in its own `_move_paused_triggers`, then drops them for the copy. A rerun keeps
 *  the first saved SQL, so a stopped run's triggers still come back. */
async function triggersOff(db) {
  const paused = (await triggerList(db)).filter(trigger => writes(trigger.sql));
  await db.prepare(`CREATE TABLE IF NOT EXISTS ${PAUSED} (name TEXT PRIMARY KEY, sql TEXT NOT NULL)`).run();
  const save = db.prepare(`INSERT OR IGNORE INTO ${PAUSED} (name, sql) VALUES (?, ?)`);
  if (paused.length) {
    await db.batch([...paused.map(({ name, sql }) => save.bind(name, sql)), ...paused.map(({ name }) => db.prepare(`DROP TRIGGER IF EXISTS ${quote(name)}`))]);
  }
  return { triggers: paused };
}

/** Puts back the paused triggers, from the saved list and any list given, then rebuilds each search index they fill.
 *  Only the new side's own SQL comes back: an old trigger may write to a table the new side lacks. */
async function triggersOn(db, given) {
  const hasSaved = await db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").bind(PAUSED).first();
  const saved = hasSaved ? (await db.prepare(`SELECT name, sql FROM ${PAUSED}`).all()).results : [];
  const present = new Set((await triggerList(db)).map(trigger => trigger.name));
  const back = new Map();
  for (const { name, sql } of [...saved, ...(Array.isArray(given) ? given : [])]) {
    if (!present.has(name) && !back.has(name) && writes(sql)) back.set(name, sql);
  }
  // One batch: a trigger that fails to come back keeps the saved list for the next run.
  const statements = [...back.values()].map(sql => db.prepare(sql));
  if (hasSaved) statements.push(db.prepare(`DROP TABLE ${PAUSED}`));
  if (statements.length) await db.batch(statements);
  const virtual = (await db.prepare("SELECT name, sql FROM sqlite_master WHERE type = 'table' AND sql LIKE 'CREATE VIRTUAL TABLE%'").all()).results;
  for (const { name } of virtual.filter(table => externalContent(table.sql))) {
    await db.prepare(`INSERT INTO ${quote(name)} (${quote(name)}) VALUES ('rebuild')`).run();
  }
  return { ok: true };
}

/** Each old trigger by name on the new side. */
async function triggerCheck(from, to) {
  const [old, fresh] = await Promise.all([triggerList(from), triggerList(to)]);
  const names = new Set(fresh.map(trigger => trigger.name));
  return { old: old.length, new: fresh.length, missing: old.filter(trigger => !names.has(trigger.name)).length };
}

async function indexes(db) {
  const virtual = (await db.prepare("SELECT name, sql FROM sqlite_master WHERE type = 'table' AND sql LIKE 'CREATE VIRTUAL TABLE%'").all()).results;
  const out = [];
  for (const { name, sql } of virtual.filter(table => externalContent(table.sql))) {
    const source = /\bcontent\s*=\s*'?([A-Za-z_][A-Za-z0-9_]*)/i.exec(sql)[1];
    out.push({ name, rows: await count(db, `${name}_docsize`), source: await count(db, source) });
  }
  return { indexes: out };
}

/** The same object: size, and the ETag unless the old one came in parts, whose ETag no single upload repeats. */
const sameObject = (old, twin) => !!twin && twin.size === old.size && (old.etag.includes('-') || twin.etag === old.etag);

async function copyBucket(from, to, { cursor, limit }) {
  const listed = await from.list({ cursor, limit });
  let files = 0;
  for (const object of listed.objects) {
    if (sameObject(object, await to.head(object.key))) continue;
    const body = await from.get(object.key);
    if (!body) continue;
    await to.put(object.key, body.body, { httpMetadata: body.httpMetadata, customMetadata: body.customMetadata });
    files += 1;
  }
  return { files, cursor: listed.truncated ? listed.cursor : null };
}

async function checkBucket(from, to, { cursor, limit }) {
  const listed = await from.list({ cursor, limit });
  let missing = 0;
  let differ = 0;
  for (const object of listed.objects) {
    const twin = await to.head(object.key);
    if (!twin) missing += 1;
    else if (!sameObject(object, twin)) differ += 1;
  }
  const bytes = listed.objects.reduce((sum, object) => sum + object.size, 0);
  return { old: listed.objects.length, bytes, missing, differ, cursor: listed.truncated ? listed.cursor : null };
}

async function sizeBucket(bucket, { cursor, limit }) {
  const listed = await bucket.list({ cursor, limit });
  return { files: listed.objects.length, bytes: listed.objects.reduce((sum, object) => sum + object.size, 0), cursor: listed.truncated ? listed.cursor : null };
}

async function answer(env, ask) {
  const limit = Math.min(Math.max(Number(ask.limit) || 100, 1), 500);
  const options = { cursor: ask.cursor ?? undefined, replace: ask.replace === true, limit };
  const d1 = () => [env[`D1_OLD_${ask.pair}`], env[`D1_NEW_${ask.pair}`]];
  const r2 = () => [env[`R2_OLD_${ask.pair}`], env[`R2_NEW_${ask.pair}`]];
  const info = async () => tableInfo(d1()[0], ask.table);
  switch (ask.op) {
    case 'ping': return { ok: true };
    case 'tables': return tables(...d1());
    case 'copy': return copyPage(...d1(), await info(), options);
    case 'link': return linkPage(...d1(), await info(), options);
    case 'check': return checkPage(...d1(), await info(), options);
    case 'count': return { old: await count(d1()[0], ask.table), new: await count(d1()[1], ask.table) };
    case 'indexes': return indexes(d1()[1]);
    case 'triggers-off': return triggersOff(d1()[1]);
    case 'triggers-on': return triggersOn(d1()[1], ask.triggers);
    case 'triggers': return triggerCheck(...d1());
    case 'copy-bucket': return copyBucket(...r2(), options);
    case 'check-bucket': return checkBucket(...r2(), options);
    case 'size-bucket': return sizeBucket(r2()[1], options);
    default: throw new Error(`unknown op ${String(ask.op).slice(0, 20)}`);
  }
}

function keyed(request, env) {
  const given = new TextEncoder().encode(request.headers.get('x-move-key') ?? '');
  const key = new TextEncoder().encode(env.MOVE_KEY ?? '');
  return key.length >= 32 && given.length === key.length && crypto.subtle.timingSafeEqual(given, key);
}

export default {
  async fetch(request, env) {
    if (request.method !== 'POST' || !keyed(request, env)) return Response.json({ error: 'refused' }, { status: 403 });
    try {
      return Response.json(await answer(env, await request.json()));
    } catch (error) {
      return Response.json({ error: String(error?.message ?? error) }, { status: 500 });
    }
  },
};
