import { describe, expect, it, vi } from "vitest";
import { ANA, bucket, fakeSpaces, NOW } from "../../tests/relay";
import { SPACE_ROWS } from "../../tests/relay-v1";
import { memorySession, ownOlderFacts, relayStore, searchWords, type MemoryCaller } from "./store";
import { spaceOf, vouch } from "../apps/relay/space";

// WongStack memory's own store check, then Relay Everything's cases, over a person's space. relay-memory-plugin §3
vi.mock("node:test", async () => { const { describe, test } = await import("vitest"); return { describe, test }; });
// WongStack's memory ships its store check with no types, so the test names the one function it calls.
const CONTRACT = new URL("../../../.agents/skills/memory/store/contract.mjs", import.meta.url).href;
type Contract = { checkStore: (make: () => unknown, name: string) => void };
const { checkStore } = await import(/* @vite-ignore */ CONTRACT) as Contract;

const DEVICE = "d-mac";
const ME: MemoryCaller = { role: "admin", subject: ANA, email: "ana@example.com" };
const S1 = "claude:0a0a-0001";
const session = (id = S1, status = "captured") => ({ id, agent: "claude", host: "mac", branch: "main", cwd: "/repo", startedAt: "2026-11-05T10:00:00Z",
  endedAt: null, status, reason: null, readThrough: null, rawBytes: null });

/** A fresh space for Ana with a computer, and `rows` in it. */
function openSpace(rows = "") {
  const spaces = fakeSpaces();
  const sql = spaces.sql(ANA);
  sql.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('${DEVICE}', 'Mac', 'rek:${DEVICE}', '', 0, 'agent');
    ${rows}`);
  const space = spaceOf({ SPACES: spaces.SPACES, WORKBENCHES: spaces.WORKBENCHES, RELAY_BUCKET: bucket as never }, vouch("key", ANA));
  return { space, sql, as: (caller: MemoryCaller = ME) => relayStore(space, caller, DEVICE) };
}
const all = (sql: ReturnType<typeof openSpace>["sql"], query: string) => sql.prepare(query).all().map(row => ({ ...row }));
type Store = ReturnType<ReturnType<typeof openSpace>["as"]>;
const one = async (store: Store, fact: object, extra: object = {}) =>
  (await store.write({ source: "save", slug: "demo", facts: [{ type: "project", body: "A fact.", ...fact } as never], ...extra })).ids[0];
const read = async (store: Store, query: object) => (await store.facts([query]))[0];

checkStore(() => {
  const { space } = openSpace();
  return { as: (caller: MemoryCaller) => relayStore(space, caller, DEVICE) };
}, "Relay Everything's space");

describe("Relay Everything's own cases", () => {
  it("reads an older kind as its new one, filters by it, and refuses an older kind on a new fact", async () => {
    const { as } = openSpace(SPACE_ROWS);
    const store = as();
    const facts = await read(store, { everyone: true, all: true, withTags: true });
    expect(facts.map(fact => [fact.id, fact.type, fact.body, fact.superseded_by, fact.tags])).toEqual([
      [3, "project", "The battery is now 50 mAh, for a full day.", null, ["battery", "ring/charging"]],
      [2, "project", "Sam makes the shell of the ring.", null, ["ring", "sam"]],
      [1, "project", "The battery stays 40 mAh.", 3, ["battery"]]]);
    expect(facts[0]).toMatchObject({ slug: "", author: null, created_at: "2026-11-04T18:16:40Z", session_id: null, sources: [] });
    await expect(one(store, { type: "decision" })).rejects.toMatchObject({ kind: "query" });
    await expect(one(store, { body: "  " })).rejects.toMatchObject({ kind: "query" });
    await expect(one(store, { body: undefined })).rejects.toMatchObject({ kind: "query" });
    await expect(store.write({ facts: [{ restate: 1 } as never] })).rejects.toMatchObject({ kind: "query" });
    const [restated] = (await store.write({ facts: [{ restate: 3 } as never] })).ids;
    expect((await read(store, { ids: [restated], withTags: true }))[0]).toMatchObject({ body: "The battery is now 50 mAh, for a full day.", tags: ["battery", "ring/charging"] });
    await expect(one(store, { tags: ["Bad Topic"] })).rejects.toMatchObject({ kind: "query" });
    await expect(store.write({ source: "guess", facts: [] })).rejects.toMatchObject({ kind: "query" });
    const thread = await one(store, { type: "thread", body: "Is the shell done?" });
    expect((await read(store, { type: "thread" })).map(fact => fact.id)).toEqual([thread]);
    expect((await read(store, { notType: "project", everyone: true })).map(fact => fact.id)).toEqual([thread]);
  });

  it("keeps a replaced fact readable and changes no note, health sample or place", async () => {
    const { as, sql } = openSpace(SPACE_ROWS);
    const before = ["relay_notes", "relay_health", "relay_locations"].map(table => all(sql, `SELECT * FROM ${table}`));
    const store = as();
    const [next] = (await store.write({ facts: [{ type: "project", body: "Sam makes the shell and the lid.", supersedes: [2] }] })).ids;
    expect((await read(store, { ids: [2], all: true }))[0]).toMatchObject({ body: "Sam makes the shell of the ring.", superseded_by: next });
    expect(all(sql, "SELECT replaces FROM relay_memory WHERE n = 4")).toEqual([{ replaces: '["fd7mm"]' }]);
    expect(["relay_notes", "relay_health", "relay_locations"].map(table => all(sql, `SELECT * FROM ${table}`))).toEqual(before);
  });

  it("links each new fact to its chat, else its day, and checks every relay: link it names", async () => {
    const { as, sql } = openSpace(`${SPACE_ROWS}
      UPDATE relay_chats SET session_id = '0a0a-0001' WHERE id = 'c0000000-0000-4000-8000-000000000002';`);
    const store = as();
    const relay = (n: number) => all(sql, `SELECT sources, memory_sources FROM relay_memory WHERE n = ${n}`)[0];
    expect(relay(await one(store, {}, { session: session() }))).toEqual({ sources: '["relay:chat/c0000000-0000-4000-8000-000000000002"]',
      memory_sources: `["session:${S1}"]` });
    expect(relay(await one(store, {}, { createdAt: "2026-11-01T08:00:00Z" })).sources).toBe('["relay:day/2026-11-01"]');
    const named = ["relay:note/a0000000-0000-4000-8000-000000000001", "relay:day/2026-11-02", "docs/plan.md"];
    expect(relay(await one(store, { sources: named }))).toEqual({ sources: JSON.stringify(named.slice(0, 2)), memory_sources: JSON.stringify(named) });
    for (const link of ["relay:note/a0000000-0000-4000-8000-00000000000f", "relay:day/2026-13-45", "relay:day/20261101", "relay:pebble/1", "relay:x"]) {
      await expect(one(store, { sources: [link] })).rejects.toMatchObject({ kind: "query" });
    }
  });

  it("finds facts by words, topic, alias, part, time, author, branch and change, in the order asked", async () => {
    const { as } = openSpace();
    const store = as();
    const newTags = [{ name: "bike", definition: "The bike." }, { name: "cycle", definition: "Another name.", aliasOf: "bike" }];
    const charger = await one(store, { body: "The bike charger needs a new cable.", tags: ["bike/charging"] }, { newTags, session: session() });
    const cable = await one(store, { type: "thread", slug: "cables", body: "Which cable fits the charger?", tags: ["cycle"] });
    const old = await one(store, { body: "An old note on the cable.", tags: ["cable"] }, { createdAt: "2026-10-01T00:00:00Z" });
    const ids = async (query: object) => (await read(store, query)).map(fact => fact.id);
    expect(await ids({ terms: "charger needs" })).toEqual([charger, cable]);
    expect(await ids({ terms: "charger needs", order: "newest" })).toEqual([cable, charger]);
    expect(await ids({ terms: "how should" })).toEqual([]);
    expect(await ids({ order: "threads-first" })).toEqual([cable, charger, old]);
    expect(await ids({ tags: ["bike"] })).toEqual([cable, charger]);
    expect(await ids({ tags: ["cycle"] })).toEqual([cable, charger]);
    expect(await ids({ since: "2026-11-01", until: "2026-12-01" })).toEqual([cable, charger]);
    expect(await ids({ author: "ana@", notSlug: "cables", session: S1 })).toEqual([charger]);
    expect(await ids({ branch: "main" })).toEqual([charger]);
    expect(await ids({ change: "demo" })).toEqual([charger]);
    expect(await ids({ limit: 0 })).toEqual([]);
    expect(await ids({ limit: 1 })).toEqual([cable]);
    await expect(ids({ since: "last week" })).rejects.toMatchObject({ kind: "query" });
    expect(searchWords("How should the cable fit")).toEqual(["cable", "fit"]);
    expect(searchWords("how should")).toEqual(["how", "should"]);
    expect(searchWords("a b")).toEqual([]);
    // The member's own view: a branch and a change read through the member's own sessions and visible facts.
    const member = as({ role: "member", subject: ANA, email: "ana@example.com" });
    expect((await read(member, { branch: "main", change: "demo" })).map(fact => fact.id)).toEqual([charger]);
  });

  it("lists every topic with its newest definition, notes' topics too, and refuses a bad topic name", async () => {
    const { as } = openSpace(SPACE_ROWS);
    const store = as();
    await store.defineTag({ name: "battery", definition: "The ring's battery." });
    await store.defineTag({ name: "battery", definition: "The battery, in mAh.", aliasOf: null });
    await store.defineTag({ name: "bare" } as never);
    await store.write({ newTags: [{ name: "plain" } as never], facts: [] });
    const tags = await store.tags();
    expect(tags.find(tag => tag.name === "battery")).toEqual({ name: "battery", definition: "The battery, in mAh.", alias_of: null, uses: 2 });
    expect(tags.filter(tag => ["bare", "plain"].includes(String(tag.name))).map(tag => tag.definition)).toEqual([null, null]);
    expect(tags.find(tag => tag.name === "errands")).toEqual({ name: "errands", definition: null, alias_of: null, uses: 0 });
    await expect(store.defineTag({ name: "Bad Topic", definition: "No." })).rejects.toMatchObject({ kind: "query" });
    await expect(store.write({ newTags: [{ name: "Bad Topic", definition: "No." }], facts: [] })).rejects.toMatchObject({ kind: "query" });
  });

  it("gives a fact's kept transcript, else its saved chat as text, else why not", async () => {
    const { as, space, sql } = openSpace(`${SPACE_ROWS}
      UPDATE relay_chats SET session_id = '0a0a-0002' WHERE id = 'c0000000-0000-4000-8000-000000000001';`);
    const store = as();
    const kept = await one(store, {}, { session: session() });
    const saved = await one(store, {}, { session: session("claude:0a0a-0002") });
    const lost = await one(store, {}, { session: session("codex:0a0a-0003") });
    const none = await one(store, {});
    const bytes = new TextEncoder().encode('{"type":"user"}\n');
    const { key } = await store.putTranscript({ sessionId: S1, agent: "claude" }, bytes);
    expect(key).toBe(`people/${ANA}/memory/transcripts/${S1}`);
    expect([...await store.transcript({ factId: kept }) as Uint8Array]).toEqual([...bytes]);
    expect(new TextDecoder().decode(await store.transcript({ factId: saved }) as Uint8Array)).toMatch(/^you: How thick should the stiffener be\?\n/);
    expect(await store.transcript({ factId: lost })).toEqual({ missing: "no transcript was stored for this session", session: "codex:0a0a-0003" });
    sql.prepare("UPDATE relay_memory_sessions SET raw_bytes = 60000000 WHERE id = 'codex:0a0a-0003'").run();
    expect(await store.transcript({ factId: lost })).toMatchObject({ missing: expect.stringMatching(/58 MB, over the 50 MB limit/) });
    expect(await store.transcript({ factId: none })).toEqual({ missing: "this fact came from no chat", session: null });
    // A transcript whose file is gone falls back to the chat, and here there is none.
    bucket.objects.clear();
    expect(await store.transcript({ factId: kept })).toMatchObject({ missing: "no transcript was stored for this session" });
    await store.putTranscript({ sessionId: S1, agent: "claude" }, bytes);
    await space.files.removeAll();
    expect([...bucket.objects.keys()].filter(name => name.includes("memory/transcripts"))).toEqual([]);
    await expect(store.putTranscript({ sessionId: "claude:0A0A", agent: "claude" }, bytes)).rejects.toMatchObject({ kind: "query" });
    await expect(store.putTranscript({ sessionId: "codex:0a0a-0003", agent: "claude" }, bytes)).rejects.toMatchObject({ kind: "query" });
    await expect(store.putTranscript({ sessionId: "claude:0a0a-0009", agent: "claude" }, bytes)).rejects.toMatchObject({ kind: "forbidden" });
    await expect(store.putTranscript({ sessionId: S1, agent: "claude" }, new Uint8Array(50 * 1024 * 1024 + 1))).rejects.toMatchObject({ kind: "tooLarge" });
  });

  it("keeps a session's newest read and its private mark, and counts runs and consolidations", async () => {
    const { as } = openSpace();
    const store = as();
    await store.putSession({ ...session(), readThrough: 7, rawBytes: 120, endedAt: "2026-11-05T11:00:00Z", reason: "done" });
    await store.putSession(session());
    await store.putSession({ id: "codex:0d0d-0004", agent: "codex", status: "captured" });
    expect(await store.session({ id: S1 })).toMatchObject({ read_through: "7", raw_bytes: 120, ended_at: "2026-11-05T11:00:00Z", host: "mac",
      device_id: DEVICE, author: "ana@example.com", owner_subject: ANA });
    await store.putRun({ kind: "consolidation", status: "ok", counts: '{"merged":2}', reason: "x".repeat(400) });
    await store.putRun({ kind: "capture", status: "failed", host: "mac", startedAt: "2026-11-05T09:00:00Z" });
    await expect(store.putRun({ kind: "capture", status: "started" })).rejects.toMatchObject({ kind: "query" });
    await expect(store.putRun({ kind: "tidy" as never, status: "ok" })).rejects.toMatchObject({ kind: "query" });
    const stats = await store.stats();
    expect(stats.consolidations).toEqual([{ counts: '{"merged":2}' }]);
    expect(stats.totals).toEqual({ facts: 0, live: 0, sessions: 2, private: 0 });
    expect((await store.digest({})).run).toMatchObject({ kind: "capture", status: "failed", started_at: "2026-11-05T09:00:00Z" });
    expect(await store.putRun({ kind: "daily", status: "failed", day: "2026-11-05", reason: "timed out", counts: "not json" })).toEqual({ claimed: false });
    expect((await store.digest({})).daily).toMatchObject({ status: "failed", reason: "timed out", counts: {} });
    expect(await store.putRun({ kind: "daily", status: "started", day: "2026-11-05", force: true, host: "pc", startedAt: "2026-11-05T13:00:00Z" }))
      .toEqual({ claimed: true });
    expect((await store.digest({})).daily).toMatchObject({ status: "started", host: "pc", last: "2026-11-05T13:00:00Z" });
    await store.putRun({ kind: "daily", status: "started", day: "2026-11-05", force: true });
    expect((await store.digest({})).daily).toMatchObject({ status: "started", host: null, last: "2026-11-05T14:00:00Z" });
  });

  it("reads a team's facts and threads in the digest, and gives the person the facts made before the store", async () => {
    const { as, space, sql } = openSpace(SPACE_ROWS);
    const team = as({ role: "team", subject: null, email: "memory-schedule:nightly" });
    await one(team, { type: "thread", body: "A team thread." });
    const digest = await team.digest({ slug: "demo" });
    expect([digest.live, digest.threads.length, digest.fresh, digest.daily]).toEqual([3, 1, [], null]);
    await ownOlderFacts(space);
    expect(all(sql, "SELECT n, owner_subject FROM relay_memory ORDER BY n")).toEqual([{ n: 1, owner_subject: ANA }, { n: 2, owner_subject: ANA },
      { n: 3, owner_subject: ANA }, { n: 4, owner_subject: null }]);
    expect((await as().digest({})).daily).toBeNull();
  });

  it("names a memory session only as claude:<id> or codex:<id>", () => {
    expect([memorySession(S1, "claude"), memorySession("codex:ab-12", "codex"), memorySession(S1, "codex"), memorySession("claude", "claude"),
      memorySession("cursor:ab", "cursor")]).toEqual([true, true, false, false, false]);
  });
});

it("keeps the clock of the shared helpers", () => expect(Date.now()).toBe(NOW));
