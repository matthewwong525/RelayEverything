// The person's memory table: facts that are only added, each with its topics and sources, and the person's own
// columns, kept as checked values. No caller's text becomes SQL: names match NAME, and every value is bound.
import { tagged, tagValues } from "./queries.ts";
import { Refusal } from "./refusal.ts";
import type { Db } from "./store.ts";

export const MAX_COLUMNS = 20;
export const MAX_FACTS = 50;
const TEXT_CHARACTERS = 400;
const WORDS = 20;
const WORD_CHARACTERS = 40;

/** A column's name: a letter, then letters, digits or `_`, up to 30. */
const NAME = /^[a-z][a-z0-9_]{0,29}$/;
/** A topic: words of letters, digits and dashes, a `/` between a topic and its part, such as `bike/charging`. */
const TAG = /^[a-z0-9]+(?:-[a-z0-9]+)*(?:\/[a-z0-9]+(?:-[a-z0-9]+)*)*$/;
/** A link to a record: `relay:chat/<id>#<message>`, `relay:day/2026-11-04`. */
export const SOURCE = /^relay:(?:note|chat|day|night|workout|stay|event|photo)\/[A-Za-z0-9._:-]{1,64}(?:#\d{1,8})?$/;
/** The names Relay Everything keeps on every fact, and the search's own fields: no column takes one. */
const KEPT = new Set(["id", "tags", "tag", "sources", "source", "replaces", "replaced_by", "device", "client_id", "created_at", "fields",
  "q", "query", "from", "to", "all", "limit", "cursor", "timezone", "where", "changes"]);
export const TYPES = ["text", "number", "date", "yes_no", "words"] as const;
type ColumnType = (typeof TYPES)[number];
type Column = { name: string; type: ColumnType; required: boolean; note: string };
type ColumnRow = { name: string; type: ColumnType; required: number; note: string; removed_at: number | null };
type Value = string | number | boolean | string[];

/** Memory's five kinds of fact. A fact saved with an older kind keeps its word and reads as its nearest new kind. */
export const KINDS = ["user", "feedback", "project", "reference", "thread"] as const;
const OLDER_KINDS = { open: "thread", preference: "feedback", fact: "project", decision: "project", plan: "project" };
/** A fact's kind as one of the five, in SQL over its `fields`; a word no list names reads as project. */
export const kindSql = (alias: string) => `CASE json_extract(${alias}.fields, '$.kind') ${[...KINDS.map(kind => [kind, kind]),
  ...Object.entries(OLDER_KINDS)].map(([from, to]) => `WHEN '${from}' THEN '${to}'`).join(" ")} ELSE 'project' END`;
/** The next free fact number, read inside the batch that adds the fact, which a space runs alone. */
export const NEXT_NUMBER = "(SELECT coalesce(max(n), 0) + 1 FROM relay_memory)";

const now = () => Date.now();
const like = (text: string) => text.replace(/[\\%_]/g, "\\$&");

/** The live columns, and the removed ones, whose names can't come back with another type. */
export async function columnsOf(db: Db) {
  const { results } = await db.prepare("SELECT name, type, required, note, removed_at FROM relay_memory_columns ORDER BY added_at, name")
    .all<ColumnRow>();
  const live = results.filter(row => row.removed_at === null).map(({ name, type, required, note }) => ({ name, type, required: required === 1, note }));
  const removed = results.filter(row => row.removed_at !== null).map(row => ({ name: row.name, type: row.type, removedAt: row.removed_at! }));
  return { columns: live, removed };
}

/** The column changes, newest first, with the name of the device that made each. */
export async function columnChanges(db: Db, limit = 100) {
  const { results } = await db.prepare(`SELECT c.name, c.change, c.detail, coalesce(d.name, '') AS device, c.created_at FROM relay_memory_column_changes c
    LEFT JOIN relay_devices d ON d.id = c.device_id ORDER BY c.seq DESC LIMIT ?`).bind(limit).all<{ name: string; change: string; detail: string;
      device: string; created_at: number }>();
  return results.map(row => ({ name: row.name, change: row.change, column: JSON.parse(row.detail) as Partial<Column>, device: row.device,
    at: row.created_at }));
}

const isDay = (text: string) => /^\d{4}-\d{2}-\d{2}$/.test(text) && !Number.isNaN(Date.parse(text));

/** What a column takes, in words, for a refusal. */
const takes = (column: Pick<Column, "name" | "type">) => `\`${column.name}\` takes ${{ yes_no: "true or false",
  words: `a list of up to ${WORDS} short words`, date: "a day, as YYYY-MM-DD", number: "a number",
  text: `text of up to ${TEXT_CHARACTERS} characters` }[column.type]}.`;

/** Whether a value fits its column's type. */
function fits(type: ColumnType, value: unknown): value is Value {
  switch (type) {
    case "text": return typeof value === "string" && value.trim() !== "" && value.length <= TEXT_CHARACTERS;
    case "number": return typeof value === "number" && Number.isFinite(value);
    case "date": return typeof value === "string" && isDay(value);
    case "yes_no": return typeof value === "boolean";
    case "words": return Array.isArray(value) && value.length <= WORDS
      && value.every(word => typeof word === "string" && word.trim() !== "" && word.length <= WORD_CHARACTERS);
  }
}

/** A filter's text from a query, read as its column's type. */
function filterValue(column: Column, value: string | number | boolean): Value {
  const text = String(value).trim().toLowerCase();
  if (column.type === "number") {
    const number = Number(text);
    if (!text || Number.isNaN(number)) throw new Refusal(`\`${column.name}\` takes a number.`);
    return number;
  }
  if (column.type === "yes_no") {
    if (!["true", "false", "yes", "no"].includes(text)) throw new Refusal(`\`${column.name}\` takes true or false.`);
    return text === "true" || text === "yes";
  }
  return String(value);
}

export type FactFilter = { words?: string[]; tag?: string; source?: string; after?: number; before?: number; beforeId?: string; all?: boolean;
  where?: Record<string, string | number | boolean>; limit: number };

const FACT = `SELECT m.id, m.fields, m.sources, m.replaces, m.replaced_by, coalesce(d.name, '') AS device, m.created_at,
  (SELECT json_group_array(tag) FROM (SELECT tag FROM relay_memory_tags WHERE fact_id = m.id ORDER BY tag)) AS tags
  FROM relay_memory m LEFT JOIN relay_devices d ON d.id = m.device_id`;
type FactRow = { id: string; fields: string; sources: string; replaces: string; replaced_by: string | null; device: string; created_at: number; tags: string };

const shaped = (row: FactRow) => ({ id: row.id, fields: JSON.parse(row.fields) as Record<string, Value>, tags: JSON.parse(row.tags) as string[],
  sources: JSON.parse(row.sources) as string[], replaces: JSON.parse(row.replaces) as string[], replacedBy: row.replaced_by,
  device: row.device, createdAt: row.created_at });
export type Fact = ReturnType<typeof shaped>;

/** A page of facts, newest first: every word in a text or words column, a topic, a source and its messages, a time
 *  range, and a value for any live column. Only live facts, unless `all`. */
export async function factPage(db: Db, filter: FactFilter) {
  const { words = [], tag, source, after = 0, before = Number.MAX_SAFE_INTEGER, beforeId = "", all = false, where = {}, limit } = filter;
  const { columns } = await columnsOf(db);
  const clauses = ["(m.created_at < ? OR (m.created_at = ? AND m.id < ?))", "m.created_at >= ?"];
  const params: (string | number)[] = [before, before, beforeId, after];
  if (!all) clauses.push("m.replaced_by IS NULL");
  const searched = columns.filter(column => column.type === "text" || column.type === "words").map(column => `$.${column.name}`);
  for (const word of words) {
    clauses.push(`EXISTS (SELECT 1 FROM json_each(?) p WHERE CAST(json_extract(m.fields, p.value) AS TEXT) LIKE ? ESCAPE '\\')`);
    params.push(JSON.stringify(searched), `%${like(word)}%`);
  }
  if (tag !== undefined) { clauses.push(tagged("relay_memory_tags", "fact_id", "m.id")); params.push(...tagValues(tag)); }
  if (source !== undefined) {
    clauses.push("EXISTS (SELECT 1 FROM json_each(m.sources) s WHERE s.value = ? OR s.value LIKE ? ESCAPE '\\')");
    params.push(source, `${like(source)}#%`);
  }
  for (const [name, value] of Object.entries(where)) {
    const column = columns.find(live => live.name === name);
    if (!column) throw new Refusal(`No live column is named \`${name}\`. Read the columns with GET /v1/memory/columns.`);
    const wanted = filterValue(column, value);
    if (column.name === "kind" && column.type === "text") {
      // A new kind also finds the older kinds that read as it, as the store's `type` does; an older word finds itself.
      clauses.push(`(lower(json_extract(m.fields, '$.kind')) = lower(?) OR ${kindSql("m")} = lower(?))`);
      params.push(String(wanted), String(wanted));
      continue;
    }
    clauses.push(column.type === "words" ? "EXISTS (SELECT 1 FROM json_each(m.fields, ?) w WHERE lower(w.value) = lower(?))"
      : column.type === "text" ? "lower(json_extract(m.fields, ?)) = lower(?)" : "json_extract(m.fields, ?) = ?");
    params.push(`$.${column.name}`, typeof wanted === "boolean" ? Number(wanted) : wanted as string | number);
  }
  const { results } = await db.prepare(`${FACT} WHERE ${clauses.join(" AND ")} ORDER BY m.created_at DESC, m.id DESC LIMIT ?`)
    .bind(...params, limit + 1).all<FactRow>();
  const page = results.slice(0, limit);
  const last = results.length > limit ? page.at(-1)! : null;
  return { facts: page.map(shaped), columns, next: last && `${last.created_at}.${last.id}` };
}

async function factById(db: Db, id: string): Promise<Fact | null> {
  const row = await db.prepare(`${FACT} WHERE m.id = ?`).bind(id).first<FactRow>();
  return row && shaped(row);
}

/** One fact, with the facts it replaced and the fact that replaced it. */
export async function factWithHistory(db: Db, id: string) {
  const fact = await factById(db, id);
  if (!fact) return null;
  const replaced = await Promise.all(fact.replaces.map(older => factById(db, older)));
  return { ...fact, replacedFacts: replaced.filter(older => older !== null), replacedByFact: fact.replacedBy ? await factById(db, fact.replacedBy) : null };
}

export type NewFact = { clientId: string; tags: string[]; sources: string[]; replaces?: string[]; fields: Record<string, unknown> };

const BASE32 = "abcdefghijklmnopqrstuvwxyz234567";
const factId = (length: number) => `f${[...crypto.getRandomValues(new Uint8Array(length))].map(byte => BASE32[byte % 32]).join("")}`;

/** New ids for `count` facts, unused in the space: 4 letters, one more for each that was taken. */
export async function newIds(db: Db, count: number): Promise<string[]> {
  const ids: string[] = [];
  for (let length = 4; ids.length < count && length <= 6; length++) {
    const tries = [...new Set(Array.from({ length: count - ids.length }, () => factId(length)))];
    const { results } = await db.prepare("SELECT id FROM relay_memory WHERE id IN (SELECT value FROM json_each(?))")
      .bind(JSON.stringify(tries)).all<{ id: string }>();
    const taken = new Set(results.map(row => row.id));
    ids.push(...tries.filter(id => !taken.has(id) && !ids.includes(id)));
  }
  if (ids.length < count) throw new Refusal("No new fact id was free. Send the facts again.", 503);
  return ids.slice(0, count);
}

/** A fact's own values, each checked against the live columns; a required column on new facts only. */
function factFields(fields: Record<string, unknown>, columns: Column[], at: string): Record<string, Value> {
  const kept: Record<string, Value> = {};
  for (const [name, value] of Object.entries(fields)) {
    const column = columns.find(live => live.name === name);
    if (!column) throw new Refusal(`${at}: no live column is named \`${name}\`. Add it with POST /v1/memory/columns first.`);
    if (value === null || value === undefined) continue;
    if (!fits(column.type, value)) throw new Refusal(`${at}: ${takes(column)}`);
    kept[name] = value;
  }
  const missing = columns.filter(column => column.required && !(column.name in kept)).map(column => `\`${column.name}\``);
  if (missing.length) throw new Refusal(`${at}: the required ${missing.join(", ")} ${missing.length > 1 ? "are" : "is"} missing.`);
  return kept;
}

/** A tag as sent: `#battery` reads as `battery`. */
export const tagOf = (text: string) => text.replace(/^#/, "");

function checkLinks(fact: NewFact, at: string) {
  const tag = fact.tags.find(text => !TAG.test(tagOf(text)));
  if (tag !== undefined) throw new Refusal(`${at}: \`${tag}\` is not a tag: lower-case words, digits and dashes, a / before a part.`);
  const source = fact.sources.find(text => !SOURCE.test(text));
  if (source !== undefined) throw new Refusal(`${at}: \`${source}\` is not a source: relay:<note|chat|day|night|workout|stay|event|photo>/<id>.`);
}

/** Adds facts as the device, owned by the person, all or none: each is checked first. A clientId this device stored
 *  before is not stored again. A fact that replaces others marks them replaced, the only change a fact gets. */
export async function addFacts(db: Db, deviceId: string, owner: string, facts: NewFact[]) {
  const { columns } = await columnsOf(db);
  const { results: before } = await db.prepare("SELECT client_id, id FROM relay_memory WHERE device_id = ? AND client_id IN (SELECT value FROM json_each(?))")
    .bind(deviceId, JSON.stringify(facts.map(fact => fact.clientId))).all<{ client_id: string; id: string }>();
  const stored = new Map(before.map(row => [row.client_id, row.id]));
  const fresh = facts.filter((fact, index) => !stored.has(fact.clientId) && facts.findIndex(other => other.clientId === fact.clientId) === index);
  const checkedFacts = fresh.map(fact => {
    const at = `The fact ${fact.clientId}`;
    checkLinks(fact, at);
    return { ...fact, tags: [...new Set(fact.tags.map(tagOf))], replaces: [...new Set(fact.replaces ?? [])], fields: factFields(fact.fields, columns, at) };
  });
  const replaced = [...new Set(checkedFacts.flatMap(fact => fact.replaces))];
  if (checkedFacts.flatMap(fact => fact.replaces).length !== replaced.length) throw new Refusal("Two facts replace the same fact: one fact replaces it.");
  const { results: older } = await db.prepare("SELECT id, replaced_by FROM relay_memory WHERE id IN (SELECT value FROM json_each(?))")
    .bind(JSON.stringify(replaced)).all<{ id: string; replaced_by: string | null }>();
  for (const id of replaced) {
    const found = older.find(row => row.id === id);
    if (!found) throw new Refusal(`No fact has the id \`${id}\` to replace.`);
    if (found.replaced_by) throw new Refusal(`The fact \`${id}\` was replaced already, by \`${found.replaced_by}\`: replace that one.`);
  }
  const ids = await newIds(db, checkedFacts.length);
  const at = now();
  const statements = checkedFacts.flatMap((fact, index) => [
    db.prepare(`INSERT INTO relay_memory (id, fields, sources, replaces, device_id, client_id, created_at, n, owner_subject)
      VALUES (?, ?, ?, ?, ?, ?, ?, ${NEXT_NUMBER}, ?)`).bind(ids[index], JSON.stringify(fact.fields), JSON.stringify(fact.sources),
      JSON.stringify(fact.replaces), deviceId, fact.clientId, at, owner),
    ...fact.tags.map(tag => db.prepare("INSERT INTO relay_memory_tags (fact_id, tag) VALUES (?, ?)").bind(ids[index], tag)),
    ...fact.replaces.map(id => db.prepare("UPDATE relay_memory SET replaced_by = ? WHERE id = ? AND replaced_by IS NULL").bind(ids[index], id)),
  ]);
  if (statements.length) await db.batch(statements);
  const made = new Map(checkedFacts.map((fact, index) => [fact.clientId, ids[index]]));
  return { facts: facts.map(fact => ({ clientId: fact.clientId, id: made.get(fact.clientId) ?? stored.get(fact.clientId)!, added: made.has(fact.clientId)
    && facts.findIndex(other => other.clientId === fact.clientId) === facts.indexOf(fact) })) };
}

type NewColumn = { name: string; type: ColumnType; required?: boolean; note?: string };
export type ColumnChange = { add?: NewColumn[]; change?: { name: string; required?: boolean; note?: string }[]; remove?: string[] };

/** Refuses a column that can't be added: a bad name, a kept or live name, or a removed name with a new type. The
 *  input schema checks the type and the note. */
function checkAdd({ name, type }: NewColumn, old: ColumnRow | undefined) {
  if (!NAME.test(name)) throw new Refusal(`\`${name}\` is not a column name: a lower-case letter, then letters, digits or _, up to 30.`);
  if (KEPT.has(name)) throw new Refusal(`\`${name}\` is a name Relay Everything keeps. Pick another name.`);
  if (old && old.removed_at === null) throw new Refusal(`The column \`${name}\` is there already. A column's type never changes.`);
  if (old && old.type !== type) throw new Refusal(`The removed column \`${name}\` was ${old.type}: add it back as ${old.type}, or pick another name.`);
}

/** The live column of this name; a missing or removed one is refused. */
function liveColumn(byName: Map<string, ColumnRow>, name: string) {
  const old = byName.get(name);
  if (!old || old.removed_at !== null) throw new Refusal(`No live column is named \`${name}\`.`);
  return old;
}

/** Adds, changes and removes columns as the device, all or none. A type never changes, and a kept name, a 21st live
 *  column, or a removed name with a new type is refused. Each change is kept with the device. */
export async function changeColumns(db: Db, deviceId: string, { add = [], change = [], remove = [] }: ColumnChange) {
  const { results } = await db.prepare("SELECT name, type, required, note, removed_at FROM relay_memory_columns").all<ColumnRow>();
  const byName = new Map(results.map(row => [row.name, row]));
  const named = [...add.map(column => column.name), ...change.map(column => column.name), ...remove];
  if (new Set(named).size !== named.length) throw new Refusal("Name each column once in a change.");
  const at = now();
  const statements = [];
  const log = (name: string, kind: string, detail: object) => db.prepare(`INSERT INTO relay_memory_column_changes (name, change, detail, device_id,
    created_at) VALUES (?, ?, ?, ?, ?)`).bind(name, kind, JSON.stringify(detail), deviceId, at);
  for (const { name, type, required = false, note = "" } of add) {
    const old = byName.get(name);
    checkAdd({ name, type }, old);
    statements.push(old
      ? db.prepare("UPDATE relay_memory_columns SET required = ?, note = ?, removed_at = NULL WHERE name = ?").bind(Number(required), note, name)
      : db.prepare("INSERT INTO relay_memory_columns (name, type, required, note, added_at) VALUES (?, ?, ?, ?, ?)").bind(name, type, Number(required), note, at),
    log(name, "add", { name, type, required, note }));
  }
  for (const { name, required, note } of change) {
    const old = liveColumn(byName, name);
    const next = { name, type: old.type, required: required ?? old.required === 1, note: note ?? old.note };
    statements.push(db.prepare("UPDATE relay_memory_columns SET required = ?, note = ? WHERE name = ?").bind(Number(next.required), next.note, name),
      log(name, "change", next));
  }
  for (const name of remove) {
    const old = liveColumn(byName, name);
    statements.push(db.prepare("UPDATE relay_memory_columns SET removed_at = ? WHERE name = ?").bind(at, name),
      log(name, "remove", { name, type: old.type }));
  }
  const live = results.filter(row => row.removed_at === null).length + add.length - remove.length;
  if (live > MAX_COLUMNS) throw new Refusal(`The memory has at most ${MAX_COLUMNS} columns. Remove one first.`);
  if (statements.length) await db.batch(statements);
  return columnsOf(db);
}

export type TagChange = { add?: string[]; remove?: string[] };

/** Adds and removes a fact's or a note's topics as the device, each kept with it; the words never change. A fact
 *  keeps at least one topic. Null when no such fact or note is in the space. */
export async function changeTags(db: Db, deviceId: string, kind: "fact" | "note", id: string, { add = [], remove = [] }: TagChange) {
  const [table, own, records] = kind === "fact" ? ["relay_memory_tags", "fact_id", "relay_memory"] : ["relay_note_tags", "note_id", "relay_notes"];
  if (!await db.prepare(`SELECT 1 AS found FROM ${records} WHERE id = ?`).bind(id).first()) return null;
  const adding = [...new Set(add.map(tagOf))];
  const removing = [...new Set(remove.map(tagOf))];
  const bad = [...adding, ...removing].find(tag => !TAG.test(tag));
  if (bad !== undefined) throw new Refusal(`\`${bad}\` is not a tag: lower-case words, digits and dashes, a / before a part.`);
  const tags = async () => (await db.prepare(`SELECT tag FROM ${table} WHERE ${own} = ? ORDER BY tag`).bind(id).all<{ tag: string }>()).results.map(row => row.tag);
  const had = await tags();
  const next = new Set([...had.filter(tag => !removing.includes(tag)), ...adding]);
  if (kind === "fact" && !next.size) throw new Refusal("A fact keeps at least one tag: add its new topic before you remove the last.");
  const at = now();
  const link = `relay:${kind}/${id}`;
  const changed = (tag: string, change: "add" | "remove") => db.prepare("INSERT INTO relay_tag_changes (link, tag, change, device_id, created_at) VALUES (?, ?, ?, ?, ?)")
    .bind(link, tag, change, deviceId, at);
  const statements = [
    ...adding.filter(tag => !had.includes(tag)).flatMap(tag => [db.prepare(`INSERT INTO ${table} (${own}, tag) VALUES (?, ?)`).bind(id, tag), changed(tag, "add")]),
    ...removing.filter(tag => had.includes(tag) && !adding.includes(tag))
      .flatMap(tag => [db.prepare(`DELETE FROM ${table} WHERE ${own} = ? AND tag = ?`).bind(id, tag), changed(tag, "remove")]),
  ];
  if (statements.length) await db.batch(statements);
  return { id, tags: await tags() };
}
