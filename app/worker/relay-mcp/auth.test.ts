import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { database } from "../../tests/employee-access/connections";
import { ANA, BEN, fakeSpaces, makeKey, queue } from "../../tests/relay";
import { hashToken } from "../apps/relay/people";
import type { McpEnv } from "./env";
import provider, { Grants } from "./index";

const ORIGIN = "https://relay-mcp.example.com";
const SERVER = "https://relay.example.com";
const CLAUDE = "https://claude.ai/api/mcp/auth_callback";
const ctx = { waitUntil: () => {}, passThroughOnException: () => {}, props: {} } as unknown as ExecutionContext;

/** KV as the OAuth library uses it: values, their metadata, and listing by prefix. */
function fakeKv() {
  const store = new Map<string, { value: string; metadata?: unknown }>();
  return {
    get: async (key: string, options?: { type?: string }) => {
      const found = store.get(key);
      return found === undefined ? null : options?.type === "json" ? JSON.parse(found.value) : found.value;
    },
    put: async (key: string, value: string, options?: { metadata?: unknown }) => { store.set(key, { value, metadata: options?.metadata }); },
    delete: async (key: string) => { store.delete(key); },
    list: async ({ prefix = "", limit = 1000, cursor = "0" }: { prefix?: string; limit?: number; cursor?: string } = {}) => {
      const names = [...store.keys()].filter(name => name.startsWith(prefix)).sort();
      const start = Number(cursor);
      const done = start + limit >= names.length;
      return { keys: names.slice(start, start + limit).map(name => ({ name, metadata: store.get(name)!.metadata })), list_complete: done,
        ...(!done && { cursor: String(start + limit) }) };
    },
  };
}

let env: McpEnv;
let directory: ReturnType<typeof database>;
let spaces: ReturnType<typeof fakeSpaces>;
beforeEach(() => {
  directory = database();
  const person = directory.sql.prepare("INSERT INTO relay_people (id, email, created_at) VALUES (?, ?, 0)");
  person.run(ANA, "ana@example.com");
  person.run(BEN, "ben@example.com");
  spaces = fakeSpaces();
  env = { DB: directory.DB, SPACES: spaces.SPACES, RELAY_WEBHOOKS: queue, OAUTH_KV: fakeKv(), RELAY_MCP_ADDRESS: `${ORIGIN}/mcp`,
    RELAY_SERVER_URL: SERVER } as unknown as McpEnv;
});
afterEach(() => { vi.useRealTimers(); });

/** What the server does once the person is signed in: keeps a one-time code for them, valid for 5 minutes. */
async function mint(person: string, code = `code-${crypto.randomUUID()}`, life = 300_000) {
  directory.sql.prepare("INSERT INTO relay_connect_codes (code_sha256, person_id, expires_at) VALUES (?, ?, ?)")
    .run(await hashToken(code), person, Date.now() + life);
  return code;
}

/** One browser: it keeps the cookies the connector sets. */
function browser() {
  const cookies = new Map<string, string>();
  return async (path: string, init: RequestInit = {}) => {
    const headers = new Headers(init.headers);
    if (cookies.size) headers.set("Cookie", [...cookies].map(([name, value]) => `${name}=${value}`).join("; "));
    const response = await provider.fetch(new Request(new URL(path, ORIGIN), { ...init, headers }), env, ctx);
    for (const cookie of response.headers.getSetCookie()) {
      const [, name, value] = /^([^=]+)=([^;]*)/.exec(cookie)!;
      if (value) cookies.set(name, value); else cookies.delete(name);
    }
    return response;
  };
}

const post = (path: string, body: Record<string, string>) => provider.fetch(new Request(`${ORIGIN}${path}`, { method: "POST",
  body: new URLSearchParams(body) }), env, ctx);

async function register(client: object = { client_name: "Claude" }) {
  const response = await provider.fetch(new Request(`${ORIGIN}/register`, { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ redirect_uris: [CLAUDE], token_endpoint_auth_method: "none", ...client }) }), env, ctx);
  return (await response.json() as { client_id: string }).client_id;
}

const VERIFIER = "a-code-verifier-of-forty-three-characters-or-more";
const challenge = async () => Buffer.from(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(VERIFIER))).toString("base64url");

/** The consent page for a new client, in a new browser. */
async function consentPage(client?: object) {
  const clientId = await register(client);
  const redirect = (client as { redirect_uris?: string[] } | undefined)?.redirect_uris?.[0] ?? CLAUDE;
  const go = browser();
  const page = await go(`/authorize?${new URLSearchParams({ response_type: "code", client_id: clientId, redirect_uri: redirect,
    code_challenge: await challenge(), code_challenge_method: "S256", state: "app-state", resource: `${ORIGIN}/mcp` })}`);
  const html = await page.text();
  return { go, clientId, redirect, html, handle: /name="handle" value="([^"]+)"/.exec(html)?.[1] ?? "" };
}

/** Consent, then the server's sign-in as `person`: the connector's answer when the server sends them back. */
async function signIn(client?: object, person = ANA, code?: string) {
  const consent = await consentPage(client);
  const approved = await consent.go("/authorize", { method: "POST", body: new URLSearchParams({ handle: consent.handle, choice: "approve" }) });
  const server = new URL(approved.headers.get("Location")!);
  const state = server.searchParams.get("state")!;
  const back = await consent.go(`/callback?${new URLSearchParams({ code: code ?? await mint(person), state })}`);
  return { ...consent, approved, server, state, back };
}

type Tokens = { access_token: string; refresh_token: string };

/** The whole connect, ending with the AI app's tokens and client id. */
async function connectTokens(client?: object, person = ANA) {
  const { back, clientId, redirect } = await signIn(client, person);
  const code = new URL(back.headers.get("Location")!).searchParams.get("code")!;
  const answer = await post("/token", { grant_type: "authorization_code", code, redirect_uri: redirect, client_id: clientId, code_verifier: VERIFIER });
  return { clientId, ...await answer.json() as Tokens };
}
const connect = async (client?: object, person = ANA) => (await connectTokens(client, person)).access_token;

const mcp = (body: object, token?: string, headers: Record<string, string> = {}) => provider.fetch(new Request(`${ORIGIN}/mcp`, { method: "POST",
  headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream", ...token && { Authorization: `Bearer ${token}` },
    ...headers }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, ...body }) }), env, ctx);
const listTools = (token?: string, headers: Record<string, string> = {}) => mcp({ method: "tools/list" }, token, headers);
const grants = () => new Grants(ctx, env);

it("connects a person's AI app after they approve it by name and sign in on the server", async () => {
  const { html, approved, server, back } = await signIn();
  expect(html).toContain("Connect Claude to Relay Everything?");
  expect(html).toContain("and add notes, when you ask it. It can't change or delete them.");
  expect(html).toContain("<b>claude.ai</b>");
  expect(approved.status).toBe(302);
  expect(`${server.origin}${server.pathname}`).toBe(`${SERVER}/apps/relay/sign-in/connect`);
  expect([...server.searchParams.keys()]).toEqual(["state"]);
  const location = new URL(back.headers.get("Location")!);
  expect([back.status, `${location.origin}${location.pathname}`, location.searchParams.get("state")]).toEqual([302, CLAUDE, "app-state"]);
  const token = await connect();
  const answer = await listTools(token);
  expect(answer.status).toBe(200);
  expect((await answer.json() as { result: { tools: unknown[] } }).result.tools).toHaveLength(9);
});

it("reads only the space of the person who signed in", async () => {
  const note = (person: string, text: string) => {
    const sql = spaces.sql(person);
    sql.prepare("INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-1', 'Phone', 'rek:d-1', '', 0, 'phone')").run();
    sql.prepare(`INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at)
      VALUES (?, 'd-1', 'typed', 'c-1', ?, 1793800000000, 0)`).run(crypto.randomUUID(), text);
  };
  note(ANA, "Ana buys milk.");
  note(BEN, "Ben buys milk.");
  const search = async (token: string) => {
    const answer = await mcp({ method: "tools/call", params: { name: "search", arguments: { query: "milk" } } }, token);
    const { result } = await answer.json() as { result: { content: { text: string }[] } };
    return JSON.parse(result.content[0].text).notes.map((found: { text: string }) => found.text);
  };
  expect(await search(await connect())).toEqual(["Ana buys milk."]);
  expect(await search(await connect(undefined, BEN))).toEqual(["Ben buys milk."]);
});

it("lists each person's own apps newest first; one can't end another's, and an ended one's token stops at once", async () => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(Date.UTC(2026, 10, 4, 15));
  const claude = await connect();
  // Each access token lasts an hour, so the second app connects within it.
  vi.setSystemTime(Date.UTC(2026, 10, 4, 15, 30));
  const chatgpt = await connect({ client_name: "ChatGPT" });
  const bens = await connect({ client_name: "Ben's app" }, BEN);
  const listed = await grants().list(ANA);
  expect(listed).toEqual({ address: `${ORIGIN}/mcp`, apps: [
    { id: expect.any(String), name: "ChatGPT", connectedAt: Date.UTC(2026, 10, 4, 15, 30) },
    { id: expect.any(String), name: "Claude", connectedAt: Date.UTC(2026, 10, 4, 15) }] });
  expect((await grants().list(BEN)).apps.map(app => app.name)).toEqual(["Ben's app"]);
  expect(await grants().revoke(listed.apps[1].id, BEN)).toBe(false);
  expect((await listTools(claude)).status).toBe(200);
  expect(await grants().revoke(listed.apps[1].id, ANA)).toBe(true);
  expect((await listTools(claude)).status).toBe(401);
  expect((await listTools(chatgpt)).status).toBe(200);
  expect((await listTools(bens)).status).toBe(200);
  expect((await grants().list(ANA)).apps.map(app => app.name)).toEqual(["ChatGPT"]);
});

it("keeps an app in use connected, and drops it after 30 days unused", async () => {
  const DAY = 24 * 3600 * 1000;
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(Date.UTC(2026, 10, 4));
  let { clientId, refresh_token: refresh } = await connectTokens();
  const renew = () => post("/token", { grant_type: "refresh_token", refresh_token: refresh, client_id: clientId });
  // Used every 25 days, it outlives the first 30 days.
  for (const day of [25, 50, 75]) {
    vi.setSystemTime(Date.UTC(2026, 10, 4) + day * DAY);
    const answer = await renew();
    expect(answer.status, `day ${day}`).toBe(200);
    refresh = (await answer.json() as Tokens).refresh_token;
  }
  vi.setSystemTime(Date.UTC(2026, 10, 4) + 106 * DAY);
  expect(await (await renew()).json()).toMatchObject({ error: "invalid_grant" });
});

it("names an app on this computer, or one with no name by its id", async () => {
  const local = { redirect_uris: ["http://127.0.0.1:33418/callback"] };
  const { html, clientId } = await consentPage(local);
  expect(html).toContain("That is an app on this computer.");
  expect(html).toContain(`Connect ${clientId} to Relay Everything?`);
  await connect(local);
  // A client's id is 16 random characters.
  expect((await grants().list(ANA)).apps.map(app => app.name)).toEqual([expect.stringMatching(/^[A-Za-z0-9_-]{16}$/)]);
});

it("sends the AI app back refused when the person cancels", async () => {
  const { go, handle } = await consentPage();
  const cancelled = await go("/authorize", { method: "POST", body: new URLSearchParams({ handle, choice: "deny" }) });
  expect(cancelled.status).toBe(302);
  expect(new URL(cancelled.headers.get("Location")!).searchParams.get("error")).toBe("access_denied");
});

it("takes a sign-in code once, and only while it is new", async () => {
  const code = await mint(ANA);
  expect((await signIn(undefined, ANA, code)).back.status).toBe(302);
  const again = (await signIn(undefined, ANA, code)).back;
  expect([again.status, await again.text()]).toEqual([400, expect.stringContaining("This sign-in was used already, or is too old.")]);
  const old = await mint(ANA, "an-old-code", -1);
  expect((await signIn(undefined, ANA, old)).back.status).toBe(400);
  expect((await signIn(undefined, ANA, "a-made-up-code")).back.status).toBe(400);
  expect((await grants().list(ANA)).apps).toHaveLength(1);
  // A directory fault is an error, never a grant.
  env.DB = { withSession: () => { throw new Error("D1 is down"); } } as unknown as D1Database;
  await expect(signIn()).rejects.toThrow("D1 is down");
  expect((await grants().list(ANA)).apps).toHaveLength(1);
});

it("refuses a sign-in answer with no code, or with no state of its own", async () => {
  const consent = await consentPage();
  const approved = await consent.go("/authorize", { method: "POST", body: new URLSearchParams({ handle: consent.handle, choice: "approve" }) });
  const state = new URL(approved.headers.get("Location")!).searchParams.get("state")!;
  const noCode = await consent.go(`/callback?state=${state}`);
  expect([noCode.status, await noCode.text()]).toEqual([400, expect.stringContaining("The sign-in did not finish.")]);
  const code = await mint(ANA);
  expect((await consent.go(`/callback?code=${code}`)).status).toBe(400);
  // A state from another browser does not let this one in, and leaves the code for its own browser.
  expect((await browser()(`/callback?${new URLSearchParams({ code, state })}`)).status).toBe(400);
  expect((await grants().list(ANA)).apps).toEqual([]);
});

it("answers a bad connect link, an unknown page, and /mcp with no token or a device's key", async () => {
  expect((await post("/authorize", { handle: "made-up", choice: "approve" })).status).toBe(400);
  expect((await post("/authorize", { choice: "deny" })).status).toBe(400);
  const bad = await provider.fetch(new Request(`${ORIGIN}/authorize?client_id=nobody&response_type=code`), env, ctx);
  expect([bad.status, await bad.text()]).toEqual([400, expect.stringContaining("This connect link is not valid.")]);
  expect((await provider.fetch(new Request(`${ORIGIN}/admin`), env, ctx)).status).toBe(404);
  expect((await listTools()).status).toBe(401);
  expect((await listTools(undefined, { "CF-Access-Client-Id": "phone.access", "CF-Access-Client-Secret": "secret" })).status).toBe(401);
  expect((await listTools(`rek_${"x".repeat(43)}`)).status).toBe(401);
  expect((await listTools(`${ANA}:grant:forged`)).status).toBe(401);
  const metadata = await provider.fetch(new Request(`${ORIGIN}/.well-known/oauth-authorization-server`), env, ctx);
  expect(await metadata.json()).toMatchObject({ authorization_endpoint: `${ORIGIN}/authorize`, registration_endpoint: `${ORIGIN}/register` });
  const resource = await provider.fetch(new Request(`${ORIGIN}/.well-known/oauth-protected-resource/mcp`), env, ctx);
  expect(await resource.json()).toMatchObject({ resource: `${ORIGIN}/mcp`, resource_name: "Relay Everything" });
});

/** A /v1/ call to the connector, with this bearer token or key. */
const v1 = (path: string, token?: string, init: RequestInit = {}) => provider.fetch(new Request(`${ORIGIN}/v1/${path}`, { ...init,
  headers: { ...token && { Authorization: `Bearer ${token}` }, ...init.headers as Record<string, string> } }), env, ctx);
const addNote = (token: string, clientId: string) => v1("notes", token, { method: "POST", headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ clientId, text: "Order the second PCB batch." }) });

it("opens the web API to a connected app's token, which adds notes as the app and stops when it is disconnected", async () => {
  const token = await connect();
  const added = await addNote(token, "claude-note-0001");
  expect([added.status, added.headers.get("Access-Control-Allow-Origin")]).toEqual([201, "*"]);
  const { id } = await added.json() as { id: string };
  expect((await addNote(token, "claude-note-0001")).status).toBe(200);
  const found = await (await v1("notes?q=PCB", token)).json() as { notes: { id: string; device: string }[] };
  expect(found.notes.map(note => [note.id, note.device])).toEqual([[id, "Claude"]]);
  expect(await (await v1("me", token)).json()).toEqual({ device: "Claude", adds: true });
  const [app] = (await grants().list(ANA)).apps;
  expect(await grants().revoke(app.id, ANA)).toBe(true);
  expect(spaces.sql(ANA).prepare("SELECT reaches, revoked_at FROM relay_devices").all()).toEqual([{ reaches: "app", revoked_at: expect.any(Number) }]);
  const after = await v1("me", token);
  expect([after.status, await after.json()]).toEqual([401, { error: "invalid_token", error_description: expect.stringContaining("Connect the app again") }]);
  // An app disconnected before it added a note has no device row to turn off.
  const unused = await connect({ client_name: "ChatGPT" });
  expect((await v1("me", unused)).status).toBe(200);
  expect(await grants().revoke((await grants().list(ANA)).apps[0].id, ANA)).toBe(true);
  expect(spaces.sql(ANA).prepare("SELECT count(*) AS count FROM relay_devices").get()).toEqual({ count: 1 });
});

it("opens the web API to a live API key, for its own person, and refuses every other key, cookie or token", async () => {
  const keys = { api: makeKey("api"), phone: makeKey("phone"), chats: makeKey("chats"), off: makeKey("off") };
  for (const [reach, key] of Object.entries(keys)) {
    const off = reach === "off" ? 1 : null;
    spaces.sql(ANA).prepare(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches)
      VALUES (?, ?, ?, '', 0, ?, ?)`).run(`d-${reach}`, `Ana's ${reach}`, `rek:d-${reach}`, off, off ? "api" : reach);
    directory.sql.prepare("INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at, revoked_at) VALUES (?, ?, ?, ?, 0, ?)")
      .run(await hashToken(key), ANA, `d-${reach}`, off ? "api" : reach, off);
  }
  expect(await (await v1("me", keys.api)).json()).toEqual({ device: "Ana's api", adds: true });
  expect((await addNote(keys.api, "script-note-0001")).status).toBe(201);
  expect(spaces.sql(ANA).prepare("SELECT device_id FROM relay_notes").all()).toEqual([{ device_id: "d-api" }]);
  const refusal = async (response: Response) => [response.status, (await response.json() as { error_description: string }).error_description];
  expect(await refusal(await v1("me", keys.phone))).toEqual([403, "A phone or chat key only sends. Make an API key on your Relay Everything page."]);
  expect(await refusal(await v1("me", keys.chats))).toEqual([403, "A phone or chat key only sends. Make an API key on your Relay Everything page."]);
  expect(await refusal(await v1("me", keys.off))).toEqual([403, "This device key is turned off."]);
  expect(await refusal(await v1("me", makeKey("unknown")))).toEqual([403, "This key is on no list of devices."]);
  expect((await v1("me", "rek_short")).status).toBe(401);
  const none = await v1("me");
  expect([none.status, none.headers.get("WWW-Authenticate")])
    .toEqual([401, `Bearer resource_metadata="${ORIGIN}/.well-known/oauth-protected-resource/mcp"`]);
  expect((await v1("me", undefined, { headers: { Cookie: "__Host-relay_session=ana-session-token" } })).status).toBe(401);
  expect((await v1("me", undefined, { headers: { "CF-Access-Client-Id": "phone.access", "CF-Access-Client-Secret": "secret" } })).status).toBe(401);
  expect((await v1("me", `${ANA}:grant:forged`)).status).toBe(401);
  // /mcp takes only its own tokens, never an API key.
  expect((await listTools(keys.api)).status).toBe(401);
});

it("refuses a token bound to another resource", async () => {
  const token = await connect();
  env.RELAY_MCP_ADDRESS = "https://relay-mcp-staging.example.com/mcp";
  expect((await v1("me", token)).status).toBe(401);
});

it("answers a browser's preflight and the API's description with no sign-in", async () => {
  const preflight = await v1("notes", undefined, { method: "OPTIONS" });
  expect([preflight.status, preflight.headers.get("Access-Control-Allow-Headers"), preflight.headers.get("Access-Control-Allow-Methods")])
    .toEqual([204, "Authorization, Content-Type", "GET, POST"]);
  const described = await v1("openapi.json");
  expect([described.status, described.headers.get("Access-Control-Allow-Origin")]).toEqual([200, "*"]);
  expect(await described.json()).toMatchObject({ openapi: "3.1.0", servers: [{ url: ORIGIN }] });
});
