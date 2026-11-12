import { readFileSync } from "node:fs";
import { beforeEach, expect, it } from "vitest";
import { z } from "zod";
import { ANA, BEN, bucket, fakeSpaces, queue } from "../../tests/relay";
import { answer, COMPUTER_ONLY, RECONNECT, type Asker } from "./answers";
import { v1, type WebTool } from "./api";
import { vouch } from "../apps/relay/space";
import { grantAsker, keyAsker } from "./asker";
import { INPUTS } from "./inputs";
import { ANSWERS } from "./openapi";

// The web API over Ana's made-up day: each route answers what its tool answers, for the caller's own space only.
const spaceRows = readFileSync(new URL("../../tests/relay-space-rows.sql", import.meta.url), "utf8");
const ID = (n: number) => `a0000000-0000-4000-8000-00000000000${n}`;
const CHAT = (n: number) => `c0000000-0000-4000-8000-00000000000${n}`;
const env = (SPACES: DurableObjectNamespace) => ({ SPACES, WORKBENCHES: spaces.WORKBENCHES, RELAY_BUCKET: bucket as never, RELAY_WEBHOOKS: queue as never });

let spaces: ReturnType<typeof fakeSpaces>;
let script: Asker;
beforeEach(() => {
  spaces = fakeSpaces();
  spaces.sql(ANA).exec(`${spaceRows}
    INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-api', 'Backup script', 'rek:d-api', '', 0, 'api');`);
  spaces.sql(BEN).exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-ben', 'Phone', 'rek:d-ben', '', 0, 'phone');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at)
    VALUES ('${ID(7)}', 'd-ben', 'typed', 'ben-1', 'Ben: buy milk.', 1793811000000, 0)`);
  script = keyAsker(env(spaces.SPACES), vouch("key", ANA, { device: { id: "d-api", reaches: "api" } }) as never);
});

/** A /v1/ call as this caller: its status and JSON. */
async function call(path: string, asker = script, init: RequestInit = {}) {
  const response = await v1(new Request(`https://relay-mcp.example.com/v1/${path}`, init), asker);
  return { status: response.status, json: await response.json() as Record<string, unknown>, allow: response.headers.get("Allow") };
}
const post = (body: string, asker = script) => call("notes", asker, { method: "POST", body, headers: { "Content-Type": "application/json" } });

const SAME: [string, WebTool, Record<string, unknown>][] = [
  ["notes?q=the&limit=1", "search", { query: "the", limit: 1 }],
  ["notes?q=the&source=ring", "search", { query: "the", source: "ring" }],
  ["notes?from=2026-11-04&to=2026-11-05&limit=2", "timeline", { from: "2026-11-04", to: "2026-11-05", limit: 2 }],
  [`notes/${ID(1)}?timezone=Europe%2FLondon`, "fetch", { id: ID(1), timezone: "Europe/London" }],
  ["days/2026-11-04", "day_summary", { day: "2026-11-04" }],
  ["days/2026-11-07", "day_summary", { day: "2026-11-07" }],
  ["health?type=steps&from=2026-11-04T07:00&to=2026-11-04T10:00&bucket=hour", "health", { type: "steps", from: "2026-11-04T07:00", to: "2026-11-04T10:00", bucket: "hour" }],
  ["health?type=heart_rate&from=2026-11-03&to=2026-11-05", "health", { type: "heart_rate", from: "2026-11-03", to: "2026-11-05" }],
  ["nights?from=2026-11-01&to=2026-11-05&limit=1", "nights", { from: "2026-11-01", to: "2026-11-05", limit: 1 }],
  ["nights?from=2026-11-04&to=2026-11-05&stages=true", "nights", { from: "2026-11-04", to: "2026-11-05", stages: true }],
  ["nights?from=2026-11-04&to=2026-11-05&stages=false", "nights", { from: "2026-11-04", to: "2026-11-05", stages: false }],
  ["workouts?from=2026-11-01&to=2026-11-08", "workouts", { from: "2026-11-01", to: "2026-11-08" }],
  ["places?from=2026-11-04&to=2026-11-05&limit=2", "places", { from: "2026-11-04", to: "2026-11-05", limit: 2 }],
  ["places?from=2026-11-07&to=2026-11-08", "places", { from: "2026-11-07", to: "2026-11-08" }],
  ["points?id=2", "points", { id: 2 }],
  ["points?from=2026-11-07T09:00&to=2026-11-07T10:00&timezone=Europe%2FLondon", "points", { from: "2026-11-07T09:00", to: "2026-11-07T10:00", timezone: "Europe/London" }],
  ["calendar?from=2026-11-04&to=2026-11-05&limit=1", "calendar", { from: "2026-11-04", to: "2026-11-05", limit: 1 }],
  ["calendar?q=sam&from=2026-11-01&to=2026-12-01", "calendar", { query: "sam", from: "2026-11-01", to: "2026-12-01" }],
  ["health?type=weight&from=2026-11-04&to=2026-11-05", "health", { type: "weight", from: "2026-11-04", to: "2026-11-05" }],
  ["chats?q=stiffener", "search_chats", { query: "stiffener" }],
  ["chats?from=2026-11-01&to=2026-11-08&limit=2", "search_chats", { from: "2026-11-01", to: "2026-11-08", limit: 2 }],
  [`chats/${CHAT(1)}`, "read_chat", { id: CHAT(1) }],
  ["notes?tag=ring", "search", { tag: "ring" }],
  ["memory?q=battery", "memory", { query: "battery" }],
  ["memory?tag=%23battery&all=true&limit=5", "memory", { tag: "#battery", all: true, limit: 5 }],
  ["memory?kind=decision&timezone=Europe%2FLondon", "memory", { where: { kind: "decision" }, timezone: "Europe/London" }],
  ["memory/fc5kk", "read_fact", { id: "fc5kk" }],
  ["memory/columns", "columns", {}],
  ["memory/columns?changes=true", "columns", { changes: true }],
];

it("answers each route as its tool answers the same input, in the shape the OpenAPI file gives", async () => {
  for (const [path, name, input] of SAME) {
    const { status, json } = await call(path);
    expect([status, json], path).toEqual([200, await answer(name, script, z.object(INPUTS[name].input).parse(input) as never)]);
    expect(ANSWERS[name].safeParse(json).error, path).toBeUndefined();
  }
});

it("reads on with each answer's cursor, and keeps each tool's limits", async () => {
  const first = await call("notes?q=the&limit=1");
  expect(first.json.nextCursor).toBe(`1793811700000.${ID(2)}`);
  const rest = await call(`notes?q=the&cursor=${first.json.nextCursor}`);
  expect((rest.json.notes as { id: string }[]).map(note => note.id)).toEqual([ID(1)]);
  expect((await call("notes?q=the&limit=51")).status).toBe(400);
  expect((await call("notes?from=2026-11-04&to=2026-11-05&limit=101")).status).toBe(400);
  expect(await call("notes?q=")).toMatchObject({ status: 400, json: { error: "invalid_request", error_description: expect.stringMatching(/^`q`: /) } });
  expect((await call("notes?limit=2")).json.error_description).toMatch(/`from`: .*; `to`: /);
  expect((await call("notes?q=the&limit=many")).json.error_description).toMatch(/^`limit`: /);
  expect((await call("notes?q=the&color=red")).json.error_description).toContain("color");
  expect((await call("nights?from=2026-11-01&to=2026-11-05&cursor=1793767200001")).json.nights).toHaveLength(1);
  expect((await call("nights?from=2026-11-01&to=2026-11-05&stages=yes")).json.error_description).toMatch(/^`stages`: /);
  expect(await call("notes?q=the&cursor=page-2")).toMatchObject({ status: 400, json: { error_description: "That cursor is not one this connector gave." } });
});

it("lists a week's chats with no words, reads on with the cursor, and still filters by words", async () => {
  const first = await call("chats?from=2026-11-01&to=2026-11-08&limit=2");
  expect((first.json.chats as { id: string; lines: unknown[] }[]).map(chat => [chat.id, chat.lines])).toEqual([[CHAT(2), []], [CHAT(1), []]]);
  const rest = await call(`chats?from=2026-11-01&to=2026-11-08&cursor=${first.json.nextCursor}`);
  expect((rest.json.chats as { id: string }[]).map(chat => chat.id)).toEqual([CHAT(3)]);
  expect((await call("chats?q=stiffener&from=2026-11-01&to=2026-11-08")).json.chats).toMatchObject([{ id: CHAT(1) }]);
  expect((await call("chats?q=")).status).toBe(400);
});

it("reads a stay's or trip's points by an id sent as text, and refuses an id no stay or trip has", async () => {
  expect((await call("points?id=2")).json).toMatchObject({ id: 2, kind: "trip", total: 4 });
  expect(await call("points?id=99")).toMatchObject({ status: 404, json: { error: "not_found", error_description: "No stay or trip has this id." } });
  expect((await call("points?id=two")).json.error_description).toMatch(/^`id`: /);
  expect((await call("points?from=2026-11-01&to=2026-11-09")).status).toBe(400);
});

it("reads only the caller's own space: Ben's note is not found for Ana", async () => {
  expect(await call(`notes/${ID(7)}`)).toMatchObject({ status: 404, json: { error: "not_found", error_description: "No note has this id." } });
  expect((await call(`chats/${CHAT(9)}`)).status).toBe(404);
  const ben = grantAsker(env(spaces.SPACES), { personId: BEN })!;
  expect((await call(`notes/${ID(7)}`, ben)).json).toMatchObject({ id: ID(7), text: "Ben: buy milk." });
  // A path field that is not a whole escape stays as sent, and finds nothing.
  expect((await call("notes/%E0%A4%A")).status).toBe(404);
});

it("has no route that changes or deletes, and names what each address takes", async () => {
  for (const method of ["DELETE", "PUT", "PATCH"]) {
    expect(await call(`notes/${ID(1)}`, script, { method })).toMatchObject({ status: 405, allow: "GET", json: { error: "method_not_allowed" } });
  }
  expect((await call("notes", script, { method: "DELETE" })).allow).toBe("GET, POST");
  expect(await call("nothing")).toMatchObject({ status: 404, json: { error: "not_found" } });
  expect((await call("notes/a/b")).status).toBe(404);
});

it("adds a note as the key's own device, once, and refuses a body it can't read", async () => {
  const note = JSON.stringify({ clientId: "script-note-0001", text: "Back up the notes.", createdAt: "2026-11-04T18:00" });
  const added = await post(note);
  expect(added).toMatchObject({ status: 201, json: { added: true } });
  expect(ANSWERS.add_note.safeParse(added.json).success).toBe(true);
  expect(await post(note)).toEqual({ status: 200, json: { id: added.json.id, added: false }, allow: null });
  expect(spaces.sql(ANA).prepare("SELECT device_id, recorded_at FROM relay_notes WHERE id = ?").get(added.json.id as string))
    .toEqual({ device_id: "d-api", recorded_at: Date.UTC(2026, 10, 4, 23) });
  for (const bad of ["{", "[1]", "null", '"text"']) expect((await post(bad)).json.error_description, bad).toBe("Send a JSON object.");
  expect((await post(JSON.stringify({ clientId: "script-note-0002", text: "Hi", device: "x" }))).status).toBe(400);
  const old = grantAsker(env(spaces.SPACES), { personId: ANA })!;
  expect(await post(JSON.stringify({ clientId: "app-note-0001", text: "Hi" }), old)).toMatchObject({ status: 403, json: { error: "forbidden", error_description: RECONNECT } });
});

it("tells the caller who it is, and reads no data to do it", async () => {
  expect((await call("me")).json).toEqual({ device: "Backup script", adds: true });
  const app = grantAsker(env(spaces.SPACES), { personId: ANA, adds: true, deviceId: "e-1", name: "Claude" })!;
  expect((await call("me", app)).json).toEqual({ device: "Claude", adds: true });
  expect((await call("me", grantAsker(env(spaces.SPACES), { personId: ANA })!)).json).toEqual({ device: "", adds: false });
  const gone = keyAsker(env(spaces.SPACES), vouch("key", ANA, { device: { id: "d-gone", reaches: "api" } }) as never);
  expect((await call("me", gone)).json).toEqual({ device: "", adds: true });
  expect(ANSWERS.me.safeParse((await call("me")).json).success).toBe(true);
});

it("lets a database fault through as an error, not as an answer", async () => {
  const broken = { ...script, space: { ...script.space, db: { prepare: () => { throw new Error("The space is down"); } } } } as unknown as Asker;
  await expect(call(`notes/${ID(1)}`, broken)).rejects.toThrow("The space is down");
});

const LAPTOP = "d0000000-0000-4000-8000-000000000004";
const facts = (answer: Record<string, unknown>) => (answer.facts as { id: string }[]).map(fact => fact.id);
const decision = (clientId: string, more: Record<string, unknown> = {}) => ({ clientId, tags: ["battery"],
  sources: [`relay:chat/${CHAT(2)}#4`], fields: { kind: "decision", text: "The battery is now 60 mAh." }, ...more });

it("adds facts as the computer, once, marks the fact a new one replaces, and changes or deletes no fact", async () => {
  const laptop = keyAsker(env(spaces.SPACES), vouch("key", ANA, { device: { id: LAPTOP, reaches: "agent" } }) as never);
  const add = (body: unknown, asker = laptop) => call("memory", asker, { method: "POST", body: JSON.stringify(body) });
  const added = await add({ facts: [decision("fact-60mah-0001", { replaces: ["fc5kk"] })] });
  expect(added).toMatchObject({ status: 201, json: { facts: [{ clientId: "fact-60mah-0001", id: expect.stringMatching(/^f[a-z2-7]{4}$/), added: true }] } });
  expect(ANSWERS.add_facts.safeParse(added.json).error).toBeUndefined();
  const [{ id }] = added.json.facts as { id: string }[];
  expect((await add({ facts: [decision("fact-60mah-0001", { replaces: ["fc5kk"] })] })).json)
    .toEqual({ facts: [{ clientId: "fact-60mah-0001", id, added: false }] });
  expect(facts((await call("memory?tag=battery")).json)).toEqual([id]);
  expect(facts((await call("memory?tag=battery&all=true")).json)).toEqual([id, "fc5kk", "fb4tt"]);
  expect((await call("memory/fc5kk")).json).toMatchObject({ replacedBy: id, replacedByFact: { id, device: "Laptop" }, replacedFacts: [{ id: "fb4tt" }] });
  expect((await add({ facts: [decision("fact-again-0001", { replaces: ["fc5kk"] })] })).json.error_description)
    .toBe(`The fact \`fc5kk\` was replaced already, by \`${id}\`: replace that one.`);
  const stored = spaces.sql(ANA).prepare("SELECT * FROM relay_memory ORDER BY id").all();
  for (const bad of [{ facts: [decision("fact-notag-0001", { tags: [] })] }, { facts: [decision("fact-nosrc-0001", { sources: [] })] },
    { facts: [decision("fact-badsrc-001", { sources: ["https://example.com"] })] }, { facts: [decision("fact-nofact-001", { replaces: ["fzzzz"] })] },
    { facts: [] }]) {
    expect((await add(bad)).status, JSON.stringify(bad)).toBe(400);
  }
  expect((await add({ facts: [decision("fact-script-0001")] }, script)).json).toEqual({ error: "forbidden", error_description: COMPUTER_ONLY });
  for (const method of ["DELETE", "PUT", "PATCH"]) expect((await call("memory/fc5kk", laptop, { method })).status).toBe(405);
  expect(spaces.sql(ANA).prepare("SELECT * FROM relay_memory ORDER BY id").all()).toEqual(stored);
});

it("searches facts by words, tag, source, column and time, newest first, a page at a time", async () => {
  expect(facts((await call("memory?q=BATTERY")).json)).toEqual(["fc5kk"]);
  expect(facts((await call("memory?q=battery%2040&all=true")).json)).toEqual(["fb4tt"]);
  expect(facts((await call(`memory?source=relay:chat/${CHAT(1)}&all=true`)).json)).toEqual(["fb4tt"]);
  expect(facts((await call(`memory?source=relay:note/${ID(2)}`)).json)).toEqual(["fd7mm"]);
  expect(facts((await call("memory?kind=fact")).json)).toEqual(["fd7mm"]);
  // A new kind finds the older kinds that read as it, and each fact keeps its stored word.
  // An older word finds only itself.
  const projects = (await call("memory?kind=Project&all=true")).json as { facts: { id: string; fields: { kind: string } }[] };
  expect(projects.facts.map(fact => [fact.id, fact.fields.kind])).toEqual([["fc5kk", "decision"], ["fd7mm", "fact"], ["fb4tt", "decision"]]);
  expect(facts((await call("memory?kind=decision")).json)).toEqual(["fc5kk"]);
  expect(facts((await call("memory?kind=thread")).json)).toEqual([]);
  expect(facts((await call("memory?from=2026-11-04T17:00:00Z&to=2026-11-04T18:00:00Z")).json)).toEqual(["fd7mm"]);
  const first = await call("memory?limit=1");
  expect([facts(first.json), first.json.nextCursor]).toEqual([["fc5kk"], "1793816200000.fc5kk"]);
  expect(facts((await call(`memory?cursor=${first.json.nextCursor}`)).json)).toEqual(["fd7mm"]);
  expect((await call("memory?cursor=1793816200000.x")).json.error_description).toBe("That cursor is not one this connector gave.");
  // A cursor past the range's end reads from the end.
  expect(facts((await call("memory?to=2026-11-04T17:10:00Z&cursor=1793816200000.fc5kk")).json)).toEqual(["fd7mm"]);
  expect((await call("memory?limit=51")).status).toBe(400);
  expect((await call("memory?colour=red")).json.error_description).toMatch(/^No live column is named `colour`/);
  expect((await call("memory/columns")).json.columns).toHaveLength(2);
});

it("reads only the caller's own memory: Ben finds none of Ana's facts", async () => {
  const ben = grantAsker(env(spaces.SPACES), { personId: BEN })!;
  expect((await call("memory?q=battery", ben)).json.facts).toEqual([]);
  expect(await call("memory/fc5kk", ben)).toMatchObject({ status: 404, json: { error_description: "No fact has this id." } });
  expect((await call("memory/columns", ben)).json.columns).toHaveLength(2);
});

it("runs a computer's commands in its agents' database, refuses every other caller, and leaves the space as it was", async () => {
  const laptop = keyAsker(env(spaces.SPACES), vouch("key", ANA, { device: { id: LAPTOP, reaches: "agent" } }) as never);
  const db = (body: unknown, asker = laptop) => call("db", asker, { method: "POST", body: JSON.stringify(body) });
  const snapshot = () => ["relay_notes", "relay_memory", "relay_health"].map(table => spaces.sql(ANA).prepare(`SELECT * FROM ${table}`).all());
  const before = snapshot();
  expect(await db({ batch: [{ sql: "CREATE TABLE reading_list (title TEXT)" }, { sql: "INSERT INTO reading_list VALUES (?)", params: ["Dune"] }] }))
    .toMatchObject({ status: 200, json: { results: [{ rows: [] }, { rows: [], changed: 1 }] } });
  const read = await db({ sql: "SELECT title FROM reading_list" });
  expect(read.json).toEqual({ results: [{ rows: [{ title: "Dune" }], changed: 0 }] });
  expect(ANSWERS.db.safeParse(read.json).error).toBeUndefined();
  expect((await call("db/tables", laptop)).json).toEqual({ tables: [{ name: "reading_list", columns: ["title"], rows: 1 }] });
  expect(await db({ sql: "DELETE FROM relay_notes" })).toMatchObject({ status: 400, json: { error_description: expect.stringContaining("no such table") } });
  expect((await db({ sql: "SELECT 1", batch: [{ sql: "SELECT 2" }] })).json.error_description).toBe("Send `sql` or `batch`, not both.");
  expect((await db({})).status).toBe(400);
  const app = grantAsker(env(spaces.SPACES), { personId: ANA, adds: true, deviceId: "e-1", name: "Claude" })!;
  for (const asker of [script, app]) {
    expect((await db({ sql: "SELECT * FROM reading_list" }, asker)).json).toEqual({ error: "forbidden", error_description: COMPUTER_ONLY });
    expect((await call("db/tables", asker)).status).toBe(403);
  }
  expect(snapshot()).toEqual(before);
});
