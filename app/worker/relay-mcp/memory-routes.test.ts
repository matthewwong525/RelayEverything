import { afterEach, expect, it, vi } from "vitest";
import { httpStore } from "../../../.agents/skills/memory/store/interface.mjs";
import { ANA } from "../../tests/relay";
import { keyedConnector, V1_KEYS } from "../../tests/relay-v1";
import type { Asker } from "./answers";
import provider from "./index";
import { memoryRoute } from "./memory-routes";

// WongStack memory's store and its import on the web API: a computer's key reaches its own person's space, and
// no other key reaches either. design §2 and §10 of relay-memory-plugin
const ADDRESS = "https://relay-mcp.example.com/v1/memory";
const ctx = { waitUntil: () => {}, passThroughOnException: () => {}, props: {} } as unknown as ExecutionContext;

afterEach(() => { vi.unstubAllGlobals(); });

/** The connector, and memory's own HTTP store over it with a key. */
async function connector() {
  const keyed = await keyedConnector();
  vi.stubGlobal("fetch", (url: string, init: RequestInit) => provider.fetch(new Request(url, init), keyed.env, ctx));
  const store = (key: string) => httpStore({ url: ADDRESS, headers: () => ({ Authorization: `Bearer ${key}` }) });
  const post = (path: string, body: BodyInit | null, key = V1_KEYS.computer, method = "POST") =>
    provider.fetch(new Request(`${ADDRESS}/${path}`, { method, body, headers: { Authorization: `Bearer ${key}` } }), keyed.env, ctx);
  return { ...keyed, store, post };
}

it("answers a computer's key as its person, gives the person the facts made before the store, and refuses every other key", async () => {
  const { store, spaces } = await connector();
  const mine = store(V1_KEYS.computer);
  expect(await mine.caller()).toEqual({ role: "admin", subject: ANA, email: "ana@example.com" });
  expect(mine.role).toBe("admin");
  expect((await mine.facts([{}]) as { id: number }[][])[0].map(fact => fact.id)).toEqual([3, 2]);
  expect(spaces.sql(ANA).prepare("SELECT DISTINCT owner_subject FROM relay_memory").all()).toEqual([{ owner_subject: ANA }]);
  for (const key of [V1_KEYS.api, V1_KEYS.phone, V1_KEYS.chats]) await expect(store(key).caller()).rejects.toMatchObject({ kind: "auth" });
  // Ben's computer reads only Ben's space, which holds no fact.
  expect(await store(V1_KEYS.ben).facts([{}])).toEqual([[]]);
});

it("takes the import only as a POST from a computer, and answers a refusal as a problem", async () => {
  const { post } = await connector();
  const json = async (response: Response) => [response.status, await response.json()];
  expect(await json(await post("import", "{}"))).toEqual([200, { imported: 0, used: false, highest: 3 }]);
  expect((await post("import", null, V1_KEYS.computer, "GET")).status).toBe(405);
  expect((await post("import", "{}", V1_KEYS.api)).status).toBe(403);
  expect((await post("import", "not json")).status).toBe(400);
  expect((await post("import/transcript?session=claude:0a0a-0001", "{}")).status).toBe(404);
  await post("import", JSON.stringify({ subject: null, facts: [], tags: [],
    sessions: [{ id: "claude:0a0a-0001", status: "captured" }, { id: "claude:0a0a-0002", status: "captured" }] }));
  expect(await json(await post("import/transcript?session=claude:0a0a-0001", "{}"))).toEqual([200, { key: `people/${ANA}/memory/transcripts/claude:0a0a-0001` }]);
  expect(await json(await post("import/transcript?session=claude:0a0a-0002", new Uint8Array(50 * 1024 * 1024 + 1))))
    .toMatchObject([400, { error_description: expect.stringMatching(/is not kept/) }]);
  expect((await post("import/transcript", "{}")).status).toBe(400);
  expect((await post("notes/none", null, V1_KEYS.computer, "GET")).status).toBe(404);
});

it("names no email for a computer with none, and lets a fault that is no refusal through", async () => {
  const db = { prepare: () => ({ bind: () => ({ run: async () => ({}) }) }), batch: async () => { throw new Error("The space is down"); } };
  const asker = { space: { personId: ANA, db }, adder: { deviceId: "d-mac", name: "", kind: "agent" } } as unknown as Asker;
  const caller = await memoryRoute(new Request(`${ADDRESS}/v2/caller`, { method: "POST", body: "{}" }), asker);
  expect((await caller!.json() as { result: unknown }).result).toEqual({ role: "admin", subject: ANA, email: null });
  await expect(memoryRoute(new Request(`${ADDRESS}/import`, { method: "POST", body: "{}" }), asker)).rejects.toThrow("The space is down");
});
