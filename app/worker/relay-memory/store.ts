// WongStack memory's store in a person's space: its twelve operations over relay_memory, sessions, runs and topic
// definitions. No operation edits a fact's words or deletes one. design §3 of relay-memory-plugin
import { MAX_TRANSCRIPT_BYTES, StoreError, type Fact, type FactQuery, type FactWrite, type RunWrite } from "../../../.agents/skills/memory/store/interface.mjs";
import { KINDS, kindSql, NEXT_NUMBER, newIds, SOURCE } from "../apps/relay/memory.ts";
import type { PersonSpace, Row, SqlValue } from "../apps/relay/space.ts";

export type MemoryCaller = { role: "admin" | "member" | "reader" | "team"; subject: string | null; email: string | null };
type Read = [string, SqlValue[]];
type Kept = Record<"fields" | "sources" | "slug" | "session_id" | "author" | "created_at" | "owner_subject" | "shared" | "memory_sources", SqlValue>;
type FactRow = Kept & { tags: string[]; supersedes: number[] };
type Session = { id: string; agent: string; host?: string | null; branch?: string | null; cwd?: string | null; startedAt?: string | null;
  endedAt?: string | null; status: string; reason?: string | null; readThrough?: unknown; rawBytes?: number | null };
type Write = { session?: Session; source?: string; slug?: string; newTags?: { name: string; definition: string; aliasOf?: string | null }[];
  facts?: FactWrite[]; createdAt?: string };

const SOURCES = ["save", "backfill", "migration", "consolidation"];
const RUN_STATUS: Record<string, string[]> = { capture: ["ok", "failed"], consolidation: ["ok", "failed"], daily: ["started", "ok", "failed"] };
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const PLAIN_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
/** A memory topic: wider than Relay Everything's own, as WongStack names topics such as `node.js` or `ci_cd`. */
const TOPIC = /^[a-z0-9][a-z0-9._/-]{0,79}$/;
const MAX_BODY = 20_000;
const MAX_LIMIT = 200;
const MAX_IDS = 500;
const DAY_MS = 86_400_000;
const LATELY_DAYS = 7, LATELY_LIMIT = 8, FRESH_LIMIT = 5;
const DAILY_ROW = "kind = 'daily' AND owner_subject IS ? AND day = ?";
const NEWEST = "f.created_at DESC, f.n DESC";
const COLUMNS = `f.n AS id, coalesce(f.slug, '') AS slug, ${kindSql("f")} AS type, json_extract(f.fields, '$.text') AS body, f.author,
  strftime('%Y-%m-%dT%H:%M:%SZ', f.created_at / 1000, 'unixepoch') AS created_at, f.session_id,
  (SELECT r.n FROM relay_memory r WHERE r.id = f.replaced_by) AS superseded_by, f.owner_subject, f.shared, f.memory_sources AS sources`;
const TAGS = "(SELECT json_group_array(tag) FROM (SELECT tag FROM relay_memory_tags WHERE fact_id = f.id ORDER BY tag)) AS tags";
/** A topic's name, or the topic its newest definition says it is another name for. */
const root = (tag: string) => `coalesce((SELECT d.alias_of FROM relay_topic_defs d WHERE d.tag = ${tag} ORDER BY d.seq DESC LIMIT 1), ${tag})`;
const TAGGED = `f.id IN (SELECT t.fact_id FROM relay_memory_tags t JOIN (SELECT ${root("w.value")} AS g FROM json_each(?) w) want
  ON ${root("t.tag")} = want.g OR substr(t.tag, 1, length(want.g) + 1) = want.g || '/')`;
const TEXT_HIT = "(instr(lower(json_extract(f.fields, '$.text')), ?) > 0)";
const SESSION_UPSERT = `INSERT INTO relay_memory_sessions (id, owner_subject, device_id, author, agent, host, branch, cwd, started_at, ended_at,
  status, reason, read_through, raw_bytes, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT (id) DO UPDATE SET status = CASE WHEN relay_memory_sessions.status = 'private' THEN 'private' ELSE excluded.status END,
    reason = excluded.reason, read_through = coalesce(excluded.read_through, relay_memory_sessions.read_through),
    ended_at = coalesce(excluded.ended_at, relay_memory_sessions.ended_at), raw_bytes = coalesce(excluded.raw_bytes, relay_memory_sessions.raw_bytes),
    updated_at = excluded.updated_at`;
const FACT_INSERT = `INSERT INTO relay_memory (id, fields, sources, replaces, device_id, client_id, created_at, n, slug, session_id, author,
  owner_subject, shared, memory_sources) VALUES (?, ?, ?, (SELECT json_group_array(id) FROM relay_memory WHERE replaced_by IS NULL
  AND n IN (SELECT value FROM json_each(?)) AND (? OR owner_subject = ?)), ?, ?, ?, ${NEXT_NUMBER}, ?, ?, ?, ?, ?, ?) RETURNING n`;
/** The records a `relay:` link may name, by kind; a day is checked as a date. */
const RECORDS: Record<string, string> = { note: "relay_notes", chat: "relay_chats", photo: "relay_photos", stay: "relay_stays",
  night: "relay_nights", event: "relay_calendar_events", workout: "relay_health" };
// Words too common to match on their own: a fact sharing only *how* or *should* with a question is noise.
const FILLER = new Set(("how should what when which does the and for with that this from into about have been would could there their "
  + "them then than also just only some any all our your you are was were can will not").split(" "));

const nowIso = () => new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
const megabytes = (bytes: number) => `${Math.ceil(bytes / 1024 / 1024)} MB`;
const forbidden = (reason: string) => new StoreError(reason, { kind: "forbidden" });
const json = (value: unknown) => JSON.stringify(value);
const parsed = (text: SqlValue) => { try { return JSON.parse(String(text)) as Record<string, number>; } catch { return {}; } };
/** A time the caller sent, in ms: plain UTC and not after now keeps its date, as a backfill needs; else now. */
const factTime = (sent: unknown, time: number) => PLAIN_UTC.test(String(sent)) && Date.parse(String(sent)) <= time ? Date.parse(String(sent)) : time;

/** A topic name as given, or refused. */
function topic(name: string) {
  if (!TOPIC.test(name)) throw new StoreError(`\`${name}\` is not a topic: lower-case letters, digits, and . _ / -`);
  return name;
}

/** A new fact's body, trimmed, once its type, body and topics are good. */
function checkedFact(type: string, body: unknown, tags: string[]) {
  const text = String(body ?? "").trim();
  if (!(KINDS as readonly string[]).includes(type)) throw new StoreError(`a fact's type is one of ${KINDS.join(", ")}`);
  if (!text || text.length > MAX_BODY) throw new StoreError(`a fact's body is 1 to ${MAX_BODY} characters`);
  tags.forEach(topic);
  return text;
}

/** The significant words of a search, at most 24; filler words count only when nothing else is left. */
export function searchWords(text: string) {
  const all = [...new Set(text.toLowerCase().match(/[\p{L}\p{N}_]{3,}/gu) ?? [])];
  const meant = all.filter(word => !FILLER.has(word));
  return (meant.length ? meant : all).slice(0, 24);
}

/** A time filter's value in ms; a word that is not a time is refused. */
function msOf(text: string) {
  const ms = Date.parse(text);
  if (Number.isNaN(ms)) throw new StoreError(`\`${text}\` is not a time, such as 2026-11-12 or 2026-11-12T09:00:00Z`);
  return ms;
}

// Who sees a fact: shared facts that are not personal, and the caller's own. Only the admin's `everyone` sees all.
function visible(caller: MemoryCaller, everyone: boolean | undefined, alias = "f"): Read {
  if (everyone && caller.role === "admin") return ["1", []];
  const shared = `(${kindSql(alias)} NOT IN ('user', 'feedback') AND ${alias}.shared = 1)`;
  return caller.role === "team" ? [shared, []] : [`(${shared} OR ${alias}.owner_subject IS ?)`, [caller.subject]];
}
// Sessions and their transcripts: the caller's own, or every one for the admin.
const ownSessions = (caller: MemoryCaller, alias = "s"): Read => caller.role === "admin" ? ["1", []] : [`${alias}.owner_subject = ?`, [caller.subject]];

const FILTERS: [keyof FactQuery, string, (value: string) => SqlValue][] = [["slug", "f.slug = ?", String], ["session", "f.session_id = ?", String],
  ["notSlug", "coalesce(f.slug, '') != ?", String], ["type", `${kindSql("f")} = ?`, String], ["notType", `${kindSql("f")} != ?`, String],
  ["since", "f.created_at >= ?", msOf], ["until", "f.created_at <= ?", msOf], ["author", "f.author LIKE ?", value => `%${value}%`]];

/** One FactQuery as SQL with the caller's visibility. Terms with no word filter nothing; no limit gives every row. */
function factRead(q: FactQuery, caller: MemoryCaller): Read {
  const where: string[] = [], params: SqlValue[] = [];
  const add = (sql: string, ...values: SqlValue[]) => { where.push(sql); params.push(...values); };
  const sessions: Read[] = [];
  if (q.branch) {
    const [own, values] = ownSessions(caller, "b");
    sessions.push([`f.session_id IN (SELECT b.id FROM relay_memory_sessions b WHERE b.branch = ? AND ${own})`, [q.branch, ...values]]);
  }
  if (q.change) {
    const [seen, values] = visible(caller, q.everyone, "c");
    sessions.push([`f.session_id IN (SELECT c.session_id FROM relay_memory c WHERE c.slug = ? AND c.session_id IS NOT NULL AND ${seen})`,
      [q.change, ...values]]);
  }
  if (sessions.length) add(`(${sessions.map(([sql]) => sql).join(" OR ")})`, ...sessions.flatMap(([, values]) => values));
  if (!q.all) add("f.replaced_by IS NULL");
  if (Array.isArray(q.ids)) add("f.n IN (SELECT value FROM json_each(?))", json(q.ids.map(Number).filter(Number.isSafeInteger).slice(0, MAX_IDS)));
  for (const [key, sql, value] of FILTERS) if (q[key]) add(sql, value(String(q[key])));
  if (q.tags?.length) add(TAGGED, json(q.tags));
  const words = q.terms ? searchWords(q.terms) : [];
  const hits = `(${words.map(() => TEXT_HIT).join(" + ")})`;
  if (words.length) add(`${hits} > 0`, ...words);
  const [seen, values] = visible(caller, q.everyone);
  add(seen, ...values);
  const ranked = words.length && q.order !== "newest" && q.order !== "threads-first";
  const order = q.order === "threads-first" ? `CASE WHEN type = 'thread' THEN 0 ELSE 1 END, ${NEWEST}` : ranked ? `${hits} DESC, ${NEWEST}` : NEWEST;
  const limit = Number.isInteger(q.limit) && q.limit! >= 0 ? ` LIMIT ${Math.min(q.limit!, MAX_LIMIT)}` : "";
  return [`SELECT ${COLUMNS}${q.withTags ? `, ${TAGS}` : ""} FROM relay_memory f WHERE ${where.join(" AND ")} ORDER BY ${order}${limit}`,
    [...params, ...ranked ? words : []]];
}

const asFact = (row: Row): Fact => ({ ...row as unknown as Fact, sources: JSON.parse(String(row.sources)) as string[],
  ...typeof row.tags === "string" ? { tags: JSON.parse(row.tags) as string[] } : {} });
// The caller's newest daily run, as the digest answers it.
const dailyOf = (row: Row | undefined) => row ? { day: row.day, last: row.finished_at ?? row.started_at, status: row.status, host: row.host,
  reason: row.reason, counts: parsed(row.counts) } : null;

/** Gives the person the facts that came before the store, which name no owner: the daily build's and older ones. */
export const ownOlderFacts = (space: Pick<PersonSpace, "db" | "personId">) => space.db.prepare(`UPDATE relay_memory SET owner_subject = ?
  WHERE owner_subject IS NULL AND author IS NULL AND client_id NOT LIKE 'import:%'`).bind(space.personId).run();

/** The memory operations for one checked caller in one space; facts it adds are the device's. */
export function relayStore(space: Pick<PersonSpace, "db" | "files">, caller: MemoryCaller, deviceId: string) {
  const { db, files } = space;
  const rows = async (reads: Read[]) => await db.batch(reads.map(([sql, params]) => db.prepare(sql).bind(...params))) as Row[][];
  const first = async (sql: string, ...params: SqlValue[]) => (await rows([[sql, params]]))[0][0];
  const admin = caller.role === "admin";
  const subject = caller.subject;

  // A session row belongs to its signed-in person; a schedule has none, and a private one stays private.
  async function sessionWrite(session: Session): Promise<Read> {
    if (caller.role === "team") throw forbidden("a schedule sign-in writes team facts only, never a session");
    const row = await first("SELECT owner_subject, status FROM relay_memory_sessions WHERE id = ?", String(session.id));
    if (row && row.owner_subject !== subject) throw forbidden(`session ${session.id} belongs to another person or unassigned history`);
    if (row?.status === "private") throw forbidden(`session ${session.id} is private and cannot be captured`);
    return [SESSION_UPSERT, [String(session.id), subject, deviceId, caller.email, session.agent, session.host ?? null, session.branch ?? null,
      session.cwd ?? null, session.startedAt ?? null, session.endedAt ?? null, session.status, session.reason ?? null,
      session.readThrough == null ? null : String(session.readThrough), session.rawBytes ?? null, nowIso()]];
  }

  // The live facts a restate or close copies: only the caller's own, or any for the admin.
  async function targets(ids: number[]) {
    const [seen, values] = visible(caller, true);
    const [found] = await rows([[`SELECT f.n, f.id, f.fields, f.sources, f.slug, f.session_id, f.author, f.created_at, f.owner_subject, f.shared,
      f.memory_sources, ${TAGS} FROM relay_memory f
      WHERE f.replaced_by IS NULL AND f.n IN (SELECT value FROM json_each(?)) AND ${seen}`, [json(ids), ...values]]]);
    const byId = new Map(found.map(row => [Number(row.n), row]));
    for (const id of ids) {
      if (!byId.has(id)) throw new StoreError(`fact #${id} is not live, or not one you may see`);
      if (!admin && (subject === null || byId.get(id)!.owner_subject !== subject)) throw forbidden(`fact #${id} is someone else's; only they or the admin can restate it`);
    }
    return byId;
  }

  // True when a `relay:` link names a record in this space or a real day.
  async function linkFound(link: string) {
    const [, kind, id] = /^relay:(\w+)\/([^#]+)/.exec(link) ?? [];
    if (!SOURCE.test(link)) return false;
    if (kind === "day") return DAY.test(id) && !Number.isNaN(Date.parse(id));
    return Boolean(await first(`SELECT 1 AS found FROM ${RECORDS[kind]} WHERE CAST(id AS TEXT) = ?`, id));
  }

  // Each `relay:` link in a fact's sources, refused unless it is found.
  async function relayLinks(sources: string[]) {
    const links = sources.filter(source => source.startsWith("relay:"));
    for (const link of links) if (!await linkFound(link)) throw new StoreError(`\`${link}\` names no record in this space`);
    return links;
  }

  // A new fact's row, or a restated or closed one's with its origin kept.
  async function factRow(fact: FactWrite, at: { slug?: string; session?: Session; chat?: string; time: number; createdAt?: string; old?: Row }): Promise<FactRow> {
    const old = at.old as Kept & Row | undefined;
    if ("restate" in fact) {
      return { ...old!, tags: [...new Set([...JSON.parse(String(old!.tags)) as string[], ...fact.tags ?? []])], supersedes: [Number(old!.n)] };
    }
    const tags = "close" in fact ? JSON.parse(String(old!.tags)) as string[] : fact.tags ?? [];
    const type = "close" in fact ? "project" : fact.type;
    const body = checkedFact(type, fact.body, tags);
    if ("close" in fact) {
      return { ...old!, fields: json({ kind: type, text: body }), session_id: null, created_at: at.time, memory_sources: "[]", tags,
        supersedes: [Number(old!.n)] };
    }
    const created = factTime(at.createdAt, at.time);
    const written = fact.sources ?? (at.session ? [`session:${at.session.id}`] : []);
    const links = await relayLinks(written);
    const relay = links.length ? links : [at.chat ? `relay:chat/${at.chat}` : `relay:day/${new Date(created).toISOString().slice(0, 10)}`];
    return { fields: json({ kind: type, text: body }), sources: json(relay), slug: fact.slug || at.slug || null, session_id: at.session?.id ?? null,
      author: caller.email, created_at: created, owner_subject: subject, shared: caller.role === "reader" ? 0 : 1, memory_sources: json(written),
      tags, supersedes: (fact.supersedes ?? []).map(Number).filter(Boolean) };
  }

  /** The device's chat for a memory session, `claude:<id>`, by its own id: its `relay:` link. */
  async function chatOf(session: string) {
    const row = await first("SELECT id FROM relay_chats WHERE session_id = ? ORDER BY device_id = ? DESC, last_at DESC LIMIT 1",
      session.slice(session.indexOf(":") + 1), deviceId);
    return row ? String(row.id) : undefined;
  }

  return {
    caller: async () => caller,

    facts: async (queries: FactQuery[]) => (await rows(queries.map(q => factRead(q, caller)))).map(found => found.map(asFact)),

    async digest({ slug = null, stepTags = [] }: { slug?: string | null; stepTags?: string[] }) {
      const [seen, values] = visible(caller, false);
      const live = `f.replaced_by IS NULL AND ${seen}`;
      const kind = kindSql("f");
      // A preference is new until a finished tidy started after it; with none, for a day.
      const lastOk = `(SELECT strftime('%s', started_at) * 1000 FROM relay_memory_runs WHERE kind = 'daily' AND status = 'ok' AND owner_subject IS ?
        ORDER BY day DESC, seq DESC LIMIT 1)`;
      const team = caller.role === "team";
      const [steps, [count], threads, [run], [daily], lately, fresh] = await rows([
        // Other changes' open threads by step tag: one with two tags counts under each; untagged ones have a null tag.
        [`SELECT ft.tag, count(*) AS n FROM relay_memory f LEFT JOIN relay_memory_tags ft ON ft.fact_id = f.id AND ft.tag IN (SELECT value FROM json_each(?))
          WHERE ${live} AND ${kind} = 'thread' AND coalesce(f.slug, '') != ? GROUP BY ft.tag`, [json(stepTags), ...values, slug ?? ""]],
        [`SELECT count(*) AS live FROM relay_memory f WHERE ${live}`, values],
        [`SELECT ${COLUMNS} FROM relay_memory f WHERE ${live} AND ${kind} = 'thread' AND f.slug = ? ORDER BY f.created_at DESC`, [...values, slug ?? ""]],
        // Only this sign-in's own runs: another person's record never reaches this digest.
        ["SELECT kind, host, started_at, finished_at, status, reason, counts FROM relay_memory_runs WHERE owner_subject IS ? AND kind NOT IN ('daily', 'import') ORDER BY seq DESC LIMIT 1", [subject]],
        ["SELECT day, host, started_at, finished_at, status, reason, counts FROM relay_memory_runs WHERE kind = 'daily' AND owner_subject IS ? ORDER BY day DESC, seq DESC LIMIT 1", [subject]],
        [`SELECT ft.tag, count(*) AS n FROM relay_memory f JOIN relay_memory_tags ft ON ft.fact_id = f.id WHERE ${live} AND f.created_at >= ?
          GROUP BY ft.tag ORDER BY n DESC, ft.tag LIMIT ${LATELY_LIMIT}`, [...values, Date.now() - LATELY_DAYS * DAY_MS]],
        // A schedule owns no fact, so it has no preferences of its own.
        [`SELECT ${COLUMNS} FROM relay_memory f WHERE ${live} AND ${team ? "0" : "f.owner_subject IS ?"} AND ${kind} IN ('feedback', 'user')
          AND f.created_at > coalesce(${lastOk}, ?) ORDER BY ${NEWEST} LIMIT ${FRESH_LIMIT}`, [...values, ...team ? [] : [subject], subject, Date.now() - DAY_MS]],
      ]);
      return { live: count.live, threads: threads.map(asFact), steps, run: run ?? null, daily: dailyOf(daily), lately, fresh: fresh.map(asFact) };
    },

    // One batch, all or none: the session row, new topics, then each fact with its topics and replaces.
    async write({ session, source = "save", slug, newTags = [], facts = [], createdAt }: Write) {
      if (!SOURCES.includes(source)) throw new StoreError(`source must be one of ${SOURCES.join(", ")}`);
      const time = Date.now();
      const old = await targets(facts.map(fact => "restate" in fact ? fact.restate : "close" in fact ? fact.close : 0).map(Number).filter(Boolean));
      const statements = session ? [await sessionWrite(session)] : [];
      const chat = session && await chatOf(session.id);
      for (const tag of newTags) {
        statements.push([`INSERT INTO relay_topic_defs (tag, definition, alias_of, device_id, created_at) SELECT ?, ?, ?, ?, ?
          WHERE NOT EXISTS (SELECT 1 FROM relay_topic_defs WHERE tag = ?)`, [topic(tag.name), tag.definition ?? null, tag.aliasOf ?? null, deviceId, time, tag.name]]);
      }
      const ids = await newIds(db, facts.length);
      const inserts: number[] = [], supersedes: { asked: number[]; at: number }[] = [];
      for (const [index, fact] of facts.entries()) {
        const target = "restate" in fact ? fact.restate : "close" in fact ? fact.close : 0;
        const row = await factRow(fact, { slug, session, chat, time, createdAt, old: old.get(Number(target)) });
        inserts.push(statements.length);
        statements.push([FACT_INSERT, [ids[index]!, row.fields, row.sources, json(row.supersedes), Number(admin), subject, deviceId, `memory:${ids[index]!}`,
          row.created_at, row.slug, row.session_id, row.author, row.owner_subject, row.shared, row.memory_sources]]);
        for (const tag of row.tags) statements.push(["INSERT OR IGNORE INTO relay_memory_tags (fact_id, tag) VALUES (?, ?)", [ids[index]!, tag]]);
        if (!row.supersedes.length) continue;
        supersedes.push({ asked: row.supersedes, at: statements.length });
        // A member's supersede marks only its own facts, so a teammate's fact stays live.
        statements.push([`UPDATE relay_memory SET replaced_by = ? WHERE replaced_by IS NULL AND n IN (SELECT value FROM json_each(?))
          AND (? OR owner_subject = ?) RETURNING n`, [ids[index], json(row.supersedes), Number(admin), subject]]);
      }
      const results = await rows(statements);
      const superseded = supersedes.map(({ asked, at }) => ({ asked, marked: results[at].map(row => row.n) }));
      const unmarked = superseded.flatMap(({ asked, marked }) => asked.filter(id => !marked.includes(id)));
      const [seen, values] = visible(caller, true);
      const [left] = unmarked.length ? await rows([[`SELECT f.n AS id, f.author FROM relay_memory f WHERE f.replaced_by IS NULL
        AND f.n IN (SELECT value FROM json_each(?)) AND ${seen} ORDER BY f.n`, [json(unmarked), ...values]]]) : [[]];
      return { ids: inserts.map(at => Number(results[at][0].n)), superseded, left };
    },

    async tags() {
      const [seen, values] = visible(caller, true);
      return (await rows([[`SELECT t.name, d.definition, d.alias_of, (SELECT count(*) FROM relay_memory_tags ft JOIN relay_memory f ON f.id = ft.fact_id
        WHERE ft.tag = t.name AND ${seen}) AS uses FROM (SELECT tag AS name FROM relay_topic_defs UNION SELECT tag FROM relay_memory_tags
        UNION SELECT tag FROM relay_note_tags) t LEFT JOIN relay_topic_defs d ON d.seq = (SELECT max(seq) FROM relay_topic_defs e WHERE e.tag = t.name)
        ORDER BY t.name`, values]]))[0];
    },

    // A topic is everyone's, so only the admin defines or merges one: a new row, and the newest wins.
    async defineTag({ name, definition, aliasOf = null }: { name: string; definition: string; aliasOf?: string | null }) {
      if (!admin) throw forbidden("only the admin can change a tag; a member may add facts, but not change them");
      await rows([["INSERT INTO relay_topic_defs (tag, definition, alias_of, device_id, created_at) VALUES (?, ?, ?, ?, ?)",
        [topic(name), definition ?? null, aliasOf, deviceId, Date.now()]]]);
      return {};
    },

    async session({ id }: { id: string }) {
      const [own, values] = ownSessions(caller);
      return (await first(`SELECT * FROM relay_memory_sessions s WHERE s.id = ? AND ${own}`, String(id), ...values)) ?? null;
    },

    putSession: async (session: Session) => { await rows([await sessionWrite(session)]); return {}; },

    // The fact's chat: its kept transcript, else the saved chat with that session's id, as text, else why not.
    async transcript({ factId }: { factId: number }) {
      const [seen, values] = visible(caller, true);
      const row = await first(`SELECT f.session_id, s.transcript, s.raw_bytes, s.owner_subject FROM relay_memory f
        LEFT JOIN relay_memory_sessions s ON s.id = f.session_id WHERE f.n = ? AND ${seen}`, Number(factId), ...values);
      if (!row) return { fact: null };
      const session = row.session_id as string | null;
      const missing = (why: string) => ({ missing: why, session });
      if (!session) return missing("this fact came from no chat");
      if (!admin && row.owner_subject !== subject) return missing("only its owner and the admin can read this transcript");
      const kept = row.transcript ? await files.open(String(row.transcript)) : null;
      if (kept) return kept;
      const chat = await chatOf(session);
      if (chat) {
        const [lines] = await rows([["SELECT role, text FROM relay_chat_messages WHERE chat_id = ? ORDER BY seq", [chat]]]);
        return new TextEncoder().encode(lines.map(line => `${line.role}: ${line.text}\n`).join(""));
      }
      return missing(Number(row.raw_bytes) > MAX_TRANSCRIPT_BYTES ? `the transcript was ${megabytes(Number(row.raw_bytes))}, over the `
        + `${megabytes(MAX_TRANSCRIPT_BYTES)} limit, so it was not kept` : "no transcript was stored for this session");
    },

    // A transcript is kept in the person's files, only for a session row they own that is not private.
    async putTranscript({ sessionId, agent }: { sessionId: string; agent: string }, bytes: Uint8Array) {
      const id = String(sessionId);
      if (!memorySession(id, agent)) throw new StoreError("a transcript names its own claude or codex session");
      const row = await first("SELECT owner_subject, status FROM relay_memory_sessions WHERE id = ?", id);
      if (caller.role === "team" || !row || row.owner_subject !== subject || row.status === "private") throw forbidden("register an owned, nonprivate session before upload");
      return { key: await keepTranscript(space, id, bytes) };
    },

    // Every run is the sign-in's own. A daily run is one row per person and day: `started` claims it in one
    // statement, unless `force`, and `ok` or `failed` finishes it.
    async putRun({ kind, host, startedAt, status, reason, counts, day, force = false }: RunWrite) {
      if (!RUN_STATUS[kind]?.includes(status)) throw new StoreError(`a ${kind} run's status is one of ${(RUN_STATUS[kind] ?? ["ok", "failed"]).join(", ")}`);
      const text = typeof counts === "string" ? counts : json(counts ?? {});
      const why = reason ? String(reason).slice(0, 300) : null;
      if (kind !== "daily") {
        await rows([["INSERT INTO relay_memory_runs (kind, host, started_at, finished_at, status, reason, counts, owner_subject) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          [kind, host ?? null, startedAt || nowIso(), nowIso(), status, why, text, subject]]]);
        return {};
      }
      if (caller.role === "team") throw forbidden("a schedule sign-in runs no daily tidy");
      if (!DAY.test(String(day))) throw new StoreError("a daily run names its day as YYYY-MM-DD");
      const started = status === "started";
      const insert: Read = [`INSERT INTO relay_memory_runs (kind, host, started_at, finished_at, status, reason, counts, owner_subject, day)
        SELECT 'daily', ?, ?, ?, ?, ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM relay_memory_runs WHERE ${DAILY_ROW}) RETURNING seq`,
      [host ?? null, startedAt || nowIso(), started ? null : nowIso(), status, why, text, subject, day!, subject, day!]];
      const update: Read = started
        ? [`UPDATE relay_memory_runs SET host = ?, started_at = ?, finished_at = NULL, status = 'started', reason = NULL, counts = '{}' WHERE ${DAILY_ROW}`,
          [host ?? null, startedAt || nowIso(), subject, day!]]
        : [`UPDATE relay_memory_runs SET finished_at = ?, status = ?, reason = ?, counts = ? WHERE ${DAILY_ROW}`, [nowIso(), status, why, text, subject, day!]];
      if (started && !force) return { claimed: (await rows([insert]))[0].length > 0 };
      await rows([update, insert]);
      return { claimed: started };
    },

    async stats() {
      const [seen, values] = visible(caller, true);
      const [own, ownValues] = ownSessions(caller);
      const [types, [totals], consolidations] = await rows([
        [`SELECT ${kindSql("f")} AS type, count(*) AS n FROM relay_memory f WHERE f.replaced_by IS NULL AND ${seen} GROUP BY type ORDER BY type`, values],
        [`SELECT (SELECT count(*) FROM relay_memory f WHERE ${seen}) AS facts, (SELECT count(*) FROM relay_memory f WHERE f.replaced_by IS NULL AND ${seen}) AS live,
          (SELECT count(*) FROM relay_memory_sessions s WHERE ${own}) AS sessions,
          (SELECT count(*) FROM relay_memory_sessions s WHERE s.status = 'private' AND ${own}) AS private`, [...values, ...values, ...ownValues, ...ownValues]],
        ["SELECT counts FROM relay_memory_runs WHERE kind = 'consolidation' AND status = 'ok' AND owner_subject IS ? ORDER BY seq DESC LIMIT 10", [subject]],
      ]);
      return { types, totals, consolidations };
    },
  };
}

/** True for a memory session id of its agent: `claude:<uuid>` or `codex:<uuid>`. */
export function memorySession(id: string, agent: string) {
  const uuid = id.split(":")[1] ?? "";
  return ["claude", "codex"].includes(agent) && id === `${agent}:${uuid}` && /^[0-9a-f-]+$/.test(uuid);
}

/** Keeps a session's transcript in the person's files, up to the store's limit, and names it on the session row. */
export async function keepTranscript(space: Pick<PersonSpace, "db" | "files">, id: string, bytes: Uint8Array) {
  if (bytes.byteLength > MAX_TRANSCRIPT_BYTES) throw new StoreError(`a transcript over ${megabytes(MAX_TRANSCRIPT_BYTES)} is not kept`, { kind: "tooLarge" });
  const key = await space.files.put(`memory/transcripts/${id}`, bytes.slice().buffer);
  await space.db.prepare("UPDATE relay_memory_sessions SET transcript = ?, raw_bytes = ?, updated_at = ? WHERE id = ?")
    .bind(key, bytes.byteLength, nowIso(), id).run();
  return key;
}
