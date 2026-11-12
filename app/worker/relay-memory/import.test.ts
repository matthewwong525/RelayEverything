import { describe, expect, it } from "vitest";
import { ANA, bucket, fakeSpaces, NOW } from "../../tests/relay";
import { SPACE_ROWS } from "../../tests/relay-v1";
import { importTranscript, memoryImport } from "./import";
import { Refusal } from "../apps/relay/refusal";
import { spaceOf, vouch } from "../apps/relay/space";

// The one-time move of a WongStack memory into Ana's space: numbers, dates, authors, owners, kinds, topics and
// links come across once, and a run sent twice stores once. design §10 of relay-memory-plugin
const DEVICE = "d-mac";
const SOURCE = "src-ana";
const S1 = "claude:0a0a-0001";

function openSpace() {
  const spaces = fakeSpaces();
  const sql = spaces.sql(ANA);
  sql.exec(`${SPACE_ROWS}
    INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('${DEVICE}', 'Mac', 'rek:${DEVICE}', '', 0, 'agent');`);
  const space = spaceOf({ SPACES: spaces.SPACES, WORKBENCHES: spaces.WORKBENCHES, RELAY_BUCKET: bucket as never }, vouch("key", ANA));
  const send = (body: unknown) => memoryImport(space, DEVICE, body);
  const all = (query: string) => sql.prepare(query).all().map(row => ({ ...row }));
  return { space, sql, send, all };
}

const FACTS = [
  { id: 1, slug: "ring", type: "feedback", body: "Ana likes short answers.", author: "ana@example.com", created_at: "2026-10-02T09:00:00Z",
    session_id: S1, owner_subject: SOURCE, shared: 0, sources: [`session:${S1}`], tags: ["style", "style"] },
  { id: 2, slug: "", type: "project", body: "Ben owns the charger.", author: "ben@example.com", created_at: "2026-10-03T09:00:00Z",
    session_id: null, owner_subject: "src-ben", tags: ["battery"] },
  { id: 3, type: "project", body: "The charger is 5 V.", created_at: "not a time", owner_subject: null },
];
const SESSIONS = [
  { id: S1, owner_subject: SOURCE, author: "ana@example.com", agent: "claude", machine: "mac", branch: "main", cwd: "/repo",
    started_at: "2026-10-02T08:00:00Z", ended_at: "2026-10-02T09:30:00Z", status: "captured", read_through: 42, raw_bytes: 900,
    updated_at: "2026-10-02T09:30:00Z" },
  { id: "codex:0b0b-0002", agent: "codex", host: "pc", status: "captured", read_through: "abc" },
  { id: "codex:0c0c-0003", status: "skipped" },
];
const TAGS = [{ name: "style", definition: "How Ana likes answers." }, { name: "battery", definition: "Taken", alias_of: null }];
const chunk = (facts: object[], more: object = {}) => ({ subject: SOURCE, facts, sessions: [], tags: [], ...more });

describe("the memory import", () => {
  it("moves the space's own facts above the source's numbers, once, and only before memory used the space", async () => {
    const { send, all } = openSpace();
    expect(await send({})).toEqual({ imported: 0, used: false, highest: 3 });
    expect(await send({ start: { highest: 10 } })).toEqual({ moved: 3 });
    expect(all("SELECT id, n FROM relay_memory ORDER BY n")).toEqual([{ id: "fb4tt", n: 11 }, { id: "fd7mm", n: 12 }, { id: "fc5kk", n: 13 }]);
    await send(chunk([FACTS[2]]));
    await expect(send({ start: { highest: 20 } })).rejects.toThrow(/Send no start/);
    await expect(send({ start: { highest: -1 } })).rejects.toBeInstanceOf(Refusal);
    await expect(send(null)).rejects.toThrow(/not an import body/);
  });

  it("keeps each fact's number, date, author, owner, kind, topics and sources, and stores a resent chunk once", async () => {
    const { send, all, sql } = openSpace();
    await send({ start: { highest: 10 } });
    expect(await send(chunk(FACTS, { sessions: SESSIONS, tags: TAGS }))).toEqual({ added: 3, skipped: 0, renumbered: [] });
    expect(await send(chunk([...FACTS, FACTS[0]], { sessions: SESSIONS, tags: TAGS }))).toEqual({ added: 0, skipped: 4, renumbered: [] });
    expect(all(`SELECT n, slug, session_id, author, owner_subject, shared, fields, sources, memory_sources, created_at, device_id, client_id
      FROM relay_memory WHERE client_id LIKE 'import:%' ORDER BY n`)).toEqual([
      { n: 1, slug: "ring", session_id: S1, author: "ana@example.com", owner_subject: ANA, shared: 0,
        fields: '{"kind":"feedback","text":"Ana likes short answers."}', sources: '["relay:day/2026-10-02"]', memory_sources: `["session:${S1}"]`,
        created_at: Date.parse("2026-10-02T09:00:00Z"), device_id: DEVICE, client_id: "import:1" },
      { n: 2, slug: null, session_id: null, author: "ben@example.com", owner_subject: "src-ben", shared: 1,
        fields: '{"kind":"project","text":"Ben owns the charger."}', sources: '["relay:day/2026-10-03"]', memory_sources: "[]",
        created_at: Date.parse("2026-10-03T09:00:00Z"), device_id: DEVICE, client_id: "import:2" },
      { n: 3, slug: null, session_id: null, author: null, owner_subject: null, shared: 1, fields: '{"kind":"project","text":"The charger is 5 V."}',
        sources: '["relay:day/2026-11-05"]', memory_sources: "[]", created_at: NOW, device_id: DEVICE, client_id: "import:3" }]);
    expect(all("SELECT fact_id, tag FROM relay_memory_tags WHERE fact_id IN (SELECT id FROM relay_memory WHERE client_id LIKE 'import:%') ORDER BY tag"))
      .toHaveLength(2);
    expect(all("SELECT id, owner_subject, agent, host, read_through, raw_bytes, updated_at FROM relay_memory_sessions ORDER BY id")).toEqual([
      { id: S1, owner_subject: ANA, agent: "claude", host: "mac", read_through: "42", raw_bytes: 900, updated_at: "2026-10-02T09:30:00Z" },
      { id: "codex:0b0b-0002", owner_subject: null, agent: "codex", host: "pc", read_through: "abc", raw_bytes: null, updated_at: "2026-11-05T14:00:00Z" },
      { id: "codex:0c0c-0003", owner_subject: null, agent: null, host: null, read_through: null, raw_bytes: null, updated_at: "2026-11-05T14:00:00Z" }]);
    // A topic the space defined already keeps its own definition.
    sql.exec("INSERT INTO relay_topic_defs (tag, definition, device_id, created_at) VALUES ('ring', 'The ring.', 'x', 0)");
    await send(chunk([], { tags: [{ name: "ring" }] }));
    expect(all("SELECT tag, definition FROM relay_topic_defs ORDER BY seq")).toEqual([{ tag: "style", definition: "How Ana likes answers." },
      { tag: "battery", definition: "Taken" }, { tag: "ring", definition: "The ring." }]);
    expect(await send({})).toEqual({ imported: 3, used: true, highest: 13 });
  });

  it("gives a taken number the next free one", async () => {
    const { send } = openSpace();
    expect(await send(chunk([{ ...FACTS[1], id: 2 }, { ...FACTS[1], id: 9 }]))).toEqual({ added: 2, skipped: 0, renumbered: [{ old: 2, new: 4 }] });
  });

  it("links each replaced fact to its replacer once, refuses a fact not imported, and counts the facts by kind", async () => {
    const { send, all } = openSpace();
    await send({ start: { highest: 10 } });
    await send(chunk([...FACTS, { ...FACTS[1], id: 4, body: "Sam owns the charger." }]));
    await expect(send({ finish: { links: [{ id: 2, by: 99 }] } })).rejects.toThrow("Fact #99 was not imported");
    const counts = { live: { feedback: 1, project: 2 }, all: { feedback: 1, project: 3 } };
    expect(await send({ finish: { links: [{ id: 2, by: 4 }] } })).toEqual({ linked: 1, counts });
    expect(await send({ finish: { links: [{ id: 2, by: 4 }] } })).toEqual({ linked: 0, counts });
    const [old, by] = all("SELECT id, replaces, replaced_by FROM relay_memory WHERE client_id IN ('import:2', 'import:4') ORDER BY n");
    expect([old.replaced_by, by.replaces]).toEqual([by.id, JSON.stringify([old.id])]);
    expect(all("SELECT kind, status, counts, owner_subject FROM relay_memory_runs")).toEqual([
      { kind: "import", status: "ok", counts: '{"linked":1}', owner_subject: ANA }, { kind: "import", status: "ok", counts: '{"linked":0}', owner_subject: ANA }]);
  });

  it("counts an imported fact as live when a fact written in the space since replaced it, as the source still does", async () => {
    const { send, sql } = openSpace();
    await send(chunk(FACTS));
    const counts = { live: { feedback: 1, project: 2 }, all: { feedback: 1, project: 2 } };
    expect(await send({ finish: { links: [] } })).toEqual({ linked: 0, counts });
    sql.exec(`UPDATE relay_memory SET replaced_by = 'fc5kk' WHERE client_id = 'import:2';
      UPDATE relay_memory SET replaces = json_insert(replaces, '$[#]', (SELECT id FROM relay_memory WHERE client_id = 'import:2')) WHERE id = 'fc5kk'`);
    expect(await send({ finish: { links: [] } })).toEqual({ linked: 0, counts });
  });

  it("keeps an imported session's transcript once, and refuses one with no session", async () => {
    const { space, send } = openSpace();
    await send(chunk([FACTS[0]], { sessions: SESSIONS }));
    const bytes = new TextEncoder().encode('{"type":"user"}\n');
    expect(await importTranscript(space, S1, bytes)).toEqual({ key: `people/${ANA}/memory/transcripts/${S1}` });
    expect(await importTranscript(space, S1, bytes)).toEqual({ skipped: true });
    await expect(importTranscript(space, "claude:0a0a-0009", bytes)).rejects.toMatchObject({ status: 404 });
    await expect(importTranscript(space, "notes:1", bytes)).rejects.toMatchObject({ status: 400 });
    expect([...(await space.files.open(`people/${ANA}/memory/transcripts/${S1}`))!]).toEqual([...bytes]);
  });
});
