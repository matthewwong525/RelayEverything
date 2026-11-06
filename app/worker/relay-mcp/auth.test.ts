import { afterEach, beforeAll, beforeEach, expect, it, vi } from "vitest";
import { seeded } from "../../tests/employee-access/connections";
import { verifyIdToken } from "./auth";
import type { McpEnv } from "./env";
import provider, { Grants } from "./index";

const ORIGIN = "https://relay-mcp.example.com";
const CLAUDE = "https://claude.ai/api/mcp/auth_callback";
const ACCESS = "https://team.cloudflareaccess.com/cdn-cgi/access/sso/oidc/client-1";
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
let keys: CryptoKeyPair;
let stranger: CryptoKeyPair;
let tokenAnswer: () => Promise<Response>;
const tokenCalls: URLSearchParams[] = [];
const rsa = () => crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]),
  hash: "SHA-256" }, true, ["sign", "verify"]) as Promise<CryptoKeyPair>;

beforeAll(async () => { [keys, stranger] = await Promise.all([rsa(), rsa()]); });
beforeEach(async () => {
  env = { DB: seeded().env.DB, OAUTH_KV: fakeKv(), WONG_OWNER_EMAIL: " Matthew@example.com ", RELAY_MCP_ADDRESS: `${ORIGIN}/mcp`,
    ACCESS_CLIENT_ID: "client-1", ACCESS_CLIENT_SECRET: "access-client-secret-0123456789", ACCESS_AUTHORIZATION_URL: `${ACCESS}/authorization`,
    ACCESS_TOKEN_URL: `${ACCESS}/token`, ACCESS_JWKS_URL: `${ACCESS}/jwks` } as unknown as McpEnv;
  const jwk = { ...await crypto.subtle.exportKey("jwk", keys.publicKey), kid: "k1" };
  tokenCalls.length = 0;
  tokenAnswer = async () => Response.json({ id_token: await idToken() });
  vi.stubGlobal("fetch", vi.fn(async (input: string, init?: RequestInit) => {
    if (input === env.ACCESS_JWKS_URL) return Response.json({ keys: [jwk] });
    if (input !== env.ACCESS_TOKEN_URL) throw new TypeError("fetch failed");
    tokenCalls.push(new URLSearchParams(String(init?.body)));
    return tokenAnswer();
  }));
});
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

const text = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
/** An ID token as Access signs one; each part can be changed to make a bad one. */
async function idToken(claims: object = {}, head: object = { alg: "RS256", kid: "k1" }, key = keys.privateKey) {
  const signed = `${text(head)}.${text({ aud: "client-1", exp: Math.floor(Date.now() / 1000) + 300, email: "matthew@example.com", ...claims })}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signed));
  return `${signed}.${Buffer.from(signature).toString("base64url")}`;
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

/** Consent, then the Access sign-in: the connector's answer to Access's callback. */
async function signIn(client?: object) {
  const consent = await consentPage(client);
  const approved = await consent.go("/authorize", { method: "POST", body: new URLSearchParams({ handle: consent.handle, choice: "approve" }) });
  const access = new URL(approved.headers.get("Location")!);
  const back = await consent.go(`/callback?${new URLSearchParams({ code: "access-code", state: access.searchParams.get("state")! })}`);
  return { ...consent, approved, access, back };
}

type Tokens = { access_token: string; refresh_token: string };

/** The whole connect, ending with the AI app's tokens and client id. */
async function connectTokens(client?: object) {
  const { back, clientId, redirect } = await signIn(client);
  const code = new URL(back.headers.get("Location")!).searchParams.get("code")!;
  const answer = await post("/token", { grant_type: "authorization_code", code, redirect_uri: redirect, client_id: clientId, code_verifier: VERIFIER });
  return { clientId, ...await answer.json() as Tokens };
}
const connect = async (client?: object) => (await connectTokens(client)).access_token;

const listTools = (token?: string, headers: Record<string, string> = {}) => provider.fetch(new Request(`${ORIGIN}/mcp`, { method: "POST",
  headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream", ...token && { Authorization: `Bearer ${token}` },
    ...headers }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }) }), env, ctx);
const grants = () => new Grants(ctx, env);

it("connects the owner's AI app after they approve it by name, and its token reads Relay", async () => {
  const { html, approved, access, back } = await signIn();
  expect(html).toContain("Connect Claude to Relay Everything?");
  expect(html).toContain("<b>claude.ai</b>");
  expect(approved.status).toBe(302);
  expect(Object.fromEntries(access.searchParams)).toMatchObject({ client_id: "client-1", redirect_uri: `${ORIGIN}/callback`,
    response_type: "code", scope: "openid email" });
  expect(`${access.origin}${access.pathname}`).toBe(env.ACCESS_AUTHORIZATION_URL);
  expect(Object.fromEntries(tokenCalls[0])).toMatchObject({ grant_type: "authorization_code", code: "access-code",
    client_secret: "access-client-secret-0123456789" });
  const location = new URL(back.headers.get("Location")!);
  expect([back.status, `${location.origin}${location.pathname}`, location.searchParams.get("state")]).toEqual([302, CLAUDE, "app-state"]);
  const token = await connect();
  const answer = await listTools(token);
  expect(answer.status).toBe(200);
  expect((await answer.json() as { result: { tools: unknown[] } }).result.tools).toHaveLength(8);
});

it("lists the connected apps newest first, and a disconnected one's token stops at once", async () => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(Date.UTC(2026, 10, 4, 15));
  const claude = await connect();
  vi.setSystemTime(Date.UTC(2026, 10, 5, 15));
  const chatgpt = await connect({ client_name: "ChatGPT" });
  const listed = await grants().list();
  expect(listed).toEqual({ address: `${ORIGIN}/mcp`, apps: [
    { id: expect.any(String), name: "ChatGPT", connectedAt: Date.UTC(2026, 10, 5, 15) },
    { id: expect.any(String), name: "Claude", connectedAt: Date.UTC(2026, 10, 4, 15) }] });
  await grants().revoke(listed.apps[1].id);
  expect((await listTools(claude)).status).toBe(401);
  expect((await listTools(chatgpt)).status).toBe(200);
  expect((await grants().list()).apps.map(app => app.name)).toEqual(["ChatGPT"]);
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
  expect((await grants().list()).apps.map(app => app.name)).toEqual([expect.stringMatching(/^[A-Za-z0-9_-]{16}$/)]);
});

it("sends the AI app back refused when the owner cancels", async () => {
  const { go, handle } = await consentPage();
  const cancelled = await go("/authorize", { method: "POST", body: new URLSearchParams({ handle, choice: "deny" }) });
  expect(cancelled.status).toBe(302);
  expect(new URL(cancelled.headers.get("Location")!).searchParams.get("error")).toBe("access_denied");
  expect(tokenCalls).toEqual([]);
});

it("lets no one but the owner in, and keeps no connection for them", async () => {
  tokenAnswer = async () => Response.json({ id_token: await idToken({ email: "someone@example.com" }) });
  const { back } = await signIn();
  expect(back.status).toBe(403);
  expect(await back.text()).toContain("Only Relay Everything&#39;s owner can connect an AI app.");
  tokenAnswer = async () => Response.json({ id_token: await idToken({ email: undefined }) });
  expect((await signIn()).back.status).toBe(403);
  expect((await grants().list()).apps).toEqual([]);
});

it("refuses a sign-in it can't check", async () => {
  for (const answer of [() => Response.json({}, { status: 400 }), () => Response.json({}), async () => Response.json({ id_token: "not-a-token" })]) {
    tokenAnswer = async () => answer();
    expect((await signIn()).back.status).toBe(403);
  }
  const consent = await consentPage();
  const approved = await consent.go("/authorize", { method: "POST", body: new URLSearchParams({ handle: consent.handle, choice: "approve" }) });
  const state = new URL(approved.headers.get("Location")!).searchParams.get("state")!;
  const noCode = await consent.go(`/callback?state=${state}`);
  expect([noCode.status, await noCode.text()]).toEqual([400, expect.stringContaining("The sign-in did not finish.")]);
  expect((await consent.go("/callback?code=access-code")).status).toBe(400);
  tokenAnswer = async () => { throw new TypeError("fetch failed"); };
  const { go: again, approved: second } = await signIn().catch(() => ({ go: null, approved: null }));
  expect([again, second]).toEqual([null, null]);
  expect((await grants().list()).apps).toEqual([]);
});

it("takes an ID token only when Access signed it for this connector and it is still good", async () => {
  const now = Math.floor(Date.now() / 1000);
  expect(await verifyIdToken(await idToken(), env)).toMatchObject({ email: "matthew@example.com" });
  expect(await verifyIdToken(await idToken({ aud: ["other", "client-1"] }), env)).not.toBeNull();
  for (const token of [await idToken({}, { alg: "RS256", kid: "k1" }, stranger.privateKey), await idToken({}, { alg: "HS256", kid: "k1" }),
    await idToken({}, { alg: "RS256", kid: "k2" }), await idToken({ aud: "client-2" }), await idToken({ exp: now - 1 }),
    await idToken({ exp: undefined }), "x.y.z", ""]) {
    expect(await verifyIdToken(token, env), token).toBeNull();
  }
});

it("answers a bad connect link, an unknown page, and /mcp with no token or a device's key", async () => {
  expect((await post("/authorize", { handle: "made-up", choice: "approve" })).status).toBe(400);
  expect((await post("/authorize", { choice: "deny" })).status).toBe(400);
  const bad = await provider.fetch(new Request(`${ORIGIN}/authorize?client_id=nobody&response_type=code`), env, ctx);
  expect([bad.status, await bad.text()]).toEqual([400, expect.stringContaining("This connect link is not valid.")]);
  expect((await provider.fetch(new Request(`${ORIGIN}/admin`), env, ctx)).status).toBe(404);
  expect((await listTools()).status).toBe(401);
  expect((await listTools(undefined, { "CF-Access-Client-Id": "phone.access", "CF-Access-Client-Secret": "secret" })).status).toBe(401);
  expect((await listTools("matthew@example.com:grant:forged")).status).toBe(401);
  const metadata = await provider.fetch(new Request(`${ORIGIN}/.well-known/oauth-authorization-server`), env, ctx);
  expect(await metadata.json()).toMatchObject({ authorization_endpoint: `${ORIGIN}/authorize`, registration_endpoint: `${ORIGIN}/register` });
  const resource = await provider.fetch(new Request(`${ORIGIN}/.well-known/oauth-protected-resource/mcp`), env, ctx);
  expect(await resource.json()).toMatchObject({ resource: `${ORIGIN}/mcp`, resource_name: "Relay Everything" });
});
