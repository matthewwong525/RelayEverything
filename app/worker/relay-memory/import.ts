// The one-time move of a WongStack memory into the person's space: its facts keep their numbers, dates, authors and
// topics, and a fact already moved is skipped, so a run starts again from the top. design §10 of relay-memory-plugin
import { z } from "zod";
import { keepTranscript, memorySession } from "./store.ts";
import { kindSql, NEXT_NUMBER, newIds } from "../apps/relay/memory.ts";
import { Refusal } from "../apps/relay/refusal.ts";
import type { PersonSpace, Row, SqlValue } from "../apps/relay/space.ts";

const CHUNK = 200;
const text = z.string().nullish();
const fact = z.object({ id: z.number().int().positive(), slug: text, type: z.string(), body: z.string().min(1), author: text, created_at: z.string(),
  session_id: text, owner_subject: text, shared: z.number().optional(), sources: z.array(z.string()).optional(), tags: z.array(z.string()).optional() });
const session = z.object({ id: z.string(), owner_subject: text, author: text, agent: text, machine: text, host: text, branch: text, cwd: text,
  started_at: text, ended_at: text, status: z.string(), reason: text, read_through: z.union([z.string(), z.number()]).nullish(),
  raw_bytes: z.number().nullish(), updated_at: text });
const tag = z.object({ name: z.string().min(1), definition: text, alias_of: text });
const BODY = z.union([
  z.strictObject({ start: z.strictObject({ highest: z.number().int().min(0) }) }),
  z.strictObject({ finish: z.strictObject({ links: z.array(z.strictObject({ id: z.number().int(), by: z.number().int() })) }) }),
  z.strictObject({ subject: z.string().nullable(), facts: z.array(fact).max(CHUNK), sessions: z.array(session), tags: z.array(tag) }),
  z.strictObject({}),
]);
type Chunk = Extract<z.infer<typeof BODY>, { facts: unknown }>;
type Space = Pick<PersonSpace, "db" | "files" | "personId">;
type Read = [string, SqlValue[]];

const IMPORTED = "client_id LIKE 'import:%'";
const now = () => new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
const oldNumber = (row: Row) => Number(String(row.client_id).slice("import:".length));

async function rows(space: Space, reads: Read[]) {
  return await space.db.batch(reads.map(([sql, params]) => space.db.prepare(sql).bind(...params))) as Row[][];
}

/** How many facts came in by import, whether memory used the space, and its highest fact number. */
async function status(space: Space) {
  const [[found]] = await rows(space, [[`SELECT (SELECT count(*) FROM relay_memory WHERE ${IMPORTED}) AS imported,
    EXISTS (SELECT 1 FROM relay_memory_sessions) OR EXISTS (SELECT 1 FROM relay_memory WHERE session_id IS NOT NULL OR slug IS NOT NULL) AS used,
    (SELECT coalesce(max(n), 0) FROM relay_memory) AS highest`, []]]);
  return { imported: Number(found.imported), used: found.used === 1, highest: Number(found.highest) };
}

/** Moves the space's own facts above the source's numbers, in their order; refused once memory used the space. */
async function start(space: Space, highest: number) {
  const { used, imported } = await status(space);
  if (used || imported) throw new Refusal("Memory has used this space already, so its fact numbers are taken. Send no start.");
  const [, , [moved]] = await rows(space, [["UPDATE relay_memory SET n = -n", []], ["UPDATE relay_memory SET n = ? - n", [highest]],
    ["SELECT count(*) AS moved FROM relay_memory", []]]);
  return { moved: Number(moved.moved) };
}

/** One chunk, all or none: each fact not yet imported keeps its number when free, else takes the next free one. */
async function chunk(space: Space, deviceId: string, { subject, facts, sessions, tags }: Chunk) {
  const owner = (who: string | null | undefined) => who != null && who === subject ? space.personId : who ?? null;
  const [stored] = await rows(space, [[`SELECT client_id FROM relay_memory WHERE client_id IN (SELECT 'import:' || value FROM json_each(?))`,
    [JSON.stringify(facts.map(item => item.id))]]]);
  const there = new Set(stored.map(oldNumber));
  const fresh = facts.filter((item, index) => !there.has(item.id) && facts.findIndex(other => other.id === item.id) === index);
  const ids = await newIds(space.db, fresh.length);
  const statements: Read[] = sessions.map(row => [`INSERT INTO relay_memory_sessions (id, owner_subject, author, agent, host, branch, cwd,
    started_at, ended_at, status, reason, read_through, raw_bytes, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO NOTHING`,
  [row.id, owner(row.owner_subject), row.author ?? null, row.agent ?? null, row.machine ?? row.host ?? null, row.branch ?? null, row.cwd ?? null,
    row.started_at ?? null, row.ended_at ?? null, row.status, row.reason ?? null, row.read_through == null ? null : String(row.read_through),
    row.raw_bytes ?? null, row.updated_at ?? now()]]);
  for (const item of tags) {
    statements.push([`INSERT INTO relay_topic_defs (tag, definition, alias_of, device_id, created_at) SELECT ?, ?, ?, ?, ?
      WHERE NOT EXISTS (SELECT 1 FROM relay_topic_defs WHERE tag = ?)`, [item.name, item.definition ?? null, item.alias_of ?? null, deviceId, Date.now(), item.name]]);
  }
  const inserts: number[] = [];
  for (const [index, item] of fresh.entries()) {
    const created = Date.parse(item.created_at) || Date.now();
    inserts.push(statements.length);
    statements.push([`INSERT INTO relay_memory (id, fields, sources, device_id, client_id, created_at, n, slug, session_id, author, owner_subject,
      shared, memory_sources) VALUES (?, ?, ?, ?, ?, ?, CASE WHEN EXISTS (SELECT 1 FROM relay_memory WHERE n = ?) THEN ${NEXT_NUMBER} ELSE ? END,
      ?, ?, ?, ?, ?, ?) RETURNING n`, [ids[index], JSON.stringify({ kind: item.type, text: item.body }),
      JSON.stringify([`relay:day/${new Date(created).toISOString().slice(0, 10)}`]), deviceId, `import:${item.id}`, created, item.id, item.id,
      item.slug || null, item.session_id ?? null, item.author ?? null, owner(item.owner_subject), item.shared === 0 ? 0 : 1, JSON.stringify(item.sources ?? [])]]);
    for (const name of new Set(item.tags)) statements.push(["INSERT INTO relay_memory_tags (fact_id, tag) VALUES (?, ?)", [ids[index], name]]);
  }
  const results = await rows(space, statements);
  const renumbered = fresh.map((item, index) => ({ old: item.id, new: Number(results[inserts[index]][0].n) })).filter(pair => pair.old !== pair.new);
  return { added: fresh.length, skipped: facts.length - fresh.length, renumbered };
}

/** Links each imported fact the source marks replaced to its replacer, once; then counts the imported facts by kind,
 *  each live unless an imported fact replaced it, as the source sees it. */
async function finish(space: Space, links: { id: number; by: number }[]) {
  const [found] = await rows(space, [[`SELECT id, client_id, replaced_by FROM relay_memory WHERE client_id IN (SELECT 'import:' || value FROM json_each(?))`,
    [JSON.stringify(links.flatMap(link => [link.id, link.by]))]]]);
  const byOld = new Map(found.map(row => [oldNumber(row), row]));
  const lost = links.flatMap(link => [link.id, link.by]).find(id => !byOld.has(id));
  if (lost !== undefined) throw new Refusal(`Fact #${lost} was not imported, so its link can't be set. Send its chunk first.`);
  const open = links.filter(link => byOld.get(link.id)!.replaced_by === null);
  const statements: Read[] = open.flatMap(link => {
    const [old, by] = [byOld.get(link.id)!.id, byOld.get(link.by)!.id];
    return [["UPDATE relay_memory SET replaced_by = ? WHERE id = ?", [by, old]], ["UPDATE relay_memory SET replaces = json_insert(replaces, '$[#]', ?) WHERE id = ?", [old, by]]];
  });
  // A fact the space wrote after the switch may replace an imported one, which the source still counts as live.
  const [counts] = (await rows(space, [...statements, [`SELECT ${kindSql("m")} AS kind, NOT EXISTS (SELECT 1 FROM relay_memory r
    WHERE r.id = m.replaced_by AND r.${IMPORTED}) AS live, count(*) AS n FROM relay_memory m WHERE m.${IMPORTED} GROUP BY 1, 2`, []], ["INSERT INTO relay_memory_runs (owner_subject, kind, started_at, finished_at, status, counts) VALUES (?, 'import', ?, ?, 'ok', ?)",
    [space.personId, now(), now(), JSON.stringify({ linked: open.length })]]])).slice(statements.length);
  const tally = { live: {} as Record<string, number>, all: {} as Record<string, number> };
  for (const row of counts) {
    const kind = String(row.kind);
    tally.all[kind] = (tally.all[kind] ?? 0) + Number(row.n);
    if (row.live === 1) tally.live[kind] = Number(row.n);
  }
  return { linked: open.length, counts: tally };
}

/** `POST /v1/memory/import`: the status, the start, a chunk or the finish, by the body's shape. */
export async function memoryImport(space: Space, deviceId: string, body: unknown) {
  const parsed = BODY.safeParse(body);
  if (!parsed.success) throw new Refusal(`This is not an import body: ${parsed.error.issues[0].message}.`);
  const sent = parsed.data;
  if ("start" in sent) return start(space, sent.start.highest);
  if ("finish" in sent) return finish(space, sent.finish.links);
  if ("facts" in sent) return chunk(space, deviceId, sent as Chunk);
  return status(space);
}

/** `POST /v1/memory/import/transcript`: an imported session's transcript, kept once. */
export async function importTranscript(space: Space, id: string, bytes: Uint8Array) {
  if (!memorySession(id, id.split(":")[0])) throw new Refusal("Name the session as claude:<id> or codex:<id>.");
  const [[row]] = await rows(space, [["SELECT transcript FROM relay_memory_sessions WHERE id = ?", [id]]]);
  if (!row) throw new Refusal(`No session ${id} came in: send its chunk first.`, 404);
  if (row.transcript) return { skipped: true };
  return { key: await keepTranscript(space, id, bytes) };
}
