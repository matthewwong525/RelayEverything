import { readFileSync } from "node:fs";
import { beforeEach, expect, it } from "vitest";
import { z } from "zod";
import { ANA, BEN, fakeSpaces, queue } from "../../tests/relay";
import { answer, RECONNECT, type Asker } from "./answers";
import { v1 } from "./api";
import { vouch } from "../apps/relay/space";
import { grantAsker, keyAsker } from "./asker";
import { TOOLS, type ToolName } from "./inputs";
import { ANSWERS } from "./openapi";

// The web API over Ana's made-up day: each route answers what its tool answers, for the caller's own space only.
const spaceRows = readFileSync(new URL("../../tests/relay-space-rows.sql", import.meta.url), "utf8");
const ID = (n: number) => `a0000000-0000-4000-8000-00000000000${n}`;
const CHAT = (n: number) => `c0000000-0000-4000-8000-00000000000${n}`;
const env = (SPACES: DurableObjectNamespace) => ({ SPACES, RELAY_WEBHOOKS: queue as never });

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

const SAME: [string, ToolName, Record<string, unknown>][] = [
  ["notes?q=the&limit=1", "search", { query: "the", limit: 1 }],
  ["notes?q=the&source=ring", "search", { query: "the", source: "ring" }],
  ["notes?from=2026-11-04&to=2026-11-05&limit=2", "timeline", { from: "2026-11-04", to: "2026-11-05", limit: 2 }],
  [`notes/${ID(1)}?timezone=Europe%2FLondon`, "fetch", { id: ID(1), timezone: "Europe/London" }],
  ["days/2026-11-04", "day_summary", { day: "2026-11-04" }],
  ["health?type=steps&from=2026-11-04T07:00&to=2026-11-04T10:00&bucket=hour", "health", { type: "steps", from: "2026-11-04T07:00", to: "2026-11-04T10:00", bucket: "hour" }],
  ["health?type=heart_rate&from=2026-11-03&to=2026-11-05", "health", { type: "heart_rate", from: "2026-11-03", to: "2026-11-05" }],
  ["places?from=2026-11-04&to=2026-11-05&limit=2", "places", { from: "2026-11-04", to: "2026-11-05", limit: 2 }],
  ["chats?q=stiffener", "search_chats", { query: "stiffener" }],
  [`chats/${CHAT(1)}`, "read_chat", { id: CHAT(1) }],
];

it("answers each route as its tool answers the same input, in the shape the OpenAPI file gives", async () => {
  for (const [path, name, input] of SAME) {
    const { status, json } = await call(path);
    expect([status, json], path).toEqual([200, await answer(name, script, z.object(TOOLS[name].input).parse(input) as never)]);
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
  expect(await call("notes?q=the&cursor=page-2")).toMatchObject({ status: 400, json: { error_description: "That cursor is not one this connector gave." } });
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
  for (const bad of ["{", "[1]", "null", '"text"']) expect((await post(bad)).json.error_description, bad).toBe("Send the note as a JSON object.");
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
