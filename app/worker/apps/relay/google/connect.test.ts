import { afterEach, beforeAll, beforeEach, expect, it, vi } from "vitest";
import { ANA, BEN, ben, call, env, lost, matthew, NOW, phone, request, rows, type Who } from "../../../../tests/relay";
import { challenge } from "../sign-in/jwt";
import { googleConnect, SCOPES } from "./connect";
import { REVOKE_URL } from "./token";

const ORIGIN = "https://relay.example.com";
const CLIENT = "client.apps.googleusercontent.com";
const GOOGLE_ENV = { RELAY_GOOGLE_CLIENT_ID: CLIENT, RELAY_GOOGLE_SIGN_IN_SECRET: "client-secret" };
const encoder = new TextEncoder();
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
const part = (value: unknown) => b64(encoder.encode(JSON.stringify(value)));

let key: CryptoKeyPair;
let jwk: JsonWebKey & { kid: string };
beforeAll(async () => {
  key = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  jwk = { ...await crypto.subtle.exportKey("jwk", key.publicKey) as JsonWebKey, kid: "k1", alg: "RS256" };
});

async function idToken(nonce: string) {
  const data = `${part({ alg: "RS256", kid: "k1" })}.${part({ iss: "https://accounts.google.com", aud: CLIENT, nonce, exp: NOW / 1000 + 600,
    sub: "google-sub-ana", email: "ana@gmail.example", email_verified: true })}`;
  return `${data}.${b64(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key.privateKey, encoder.encode(data))))}`;
}

let saved: { state: string; nonce: string; verifier: string; person: string };
let tokens: (nonce: string) => Promise<Record<string, unknown> | Response>;
const sent: { url: string; body: URLSearchParams }[] = [];
beforeEach(() => {
  sent.length = 0;
  tokens = async nonce => ({ id_token: await idToken(nonce), refresh_token: "1//refresh-ana", scope: ["openid", ...SCOPES].join(" ") });
  vi.stubGlobal("fetch", vi.fn(async (url: string, init?: RequestInit) => {
    if (url.endsWith("/certs")) return Response.json({ keys: [jwk] });
    sent.push({ url, body: new URLSearchParams(String(init?.body)) });
    if (url === REVOKE_URL) return new Response(null);
    const answer = await tokens(saved.nonce);
    return answer instanceof Response ? answer : Response.json(answer);
  }));
});
afterEach(() => vi.unstubAllGlobals());

const page = (who: Who, path: string, cookie = "", more: object = GOOGLE_ENV) => {
  const asked = request(who, "GET", `${ORIGIN}/apps/relay/google/${path}`);
  if (cookie) asked.headers.set("Cookie", [asked.headers.get("Cookie"), cookie].filter(Boolean).join("; "));
  return googleConnect(asked, env(more) as never, null);
};

/** Starts a connection as `who`: Google's address and the state cookie. */
async function begin(who: Who = matthew) {
  const response = (await page(who, "connect"))!;
  const cookie = response.headers.get("Set-Cookie")!.split(";")[0];
  saved = JSON.parse(atob(cookie.slice("relay_google=".length)));
  return { response, location: new URL(response.headers.get("Location")!), cookie };
}
const back = async (who: Who, query: string, cookie: string) => (await page(who, `callback?${query}`, cookie))!.headers.get("Location");

it("sends a signed-in person to Google for the four services offline, with PKCE, state and a nonce in a short cookie", async () => {
  const { response, location } = await begin();
  expect(response.status).toBe(302);
  expect(`${location.origin}${location.pathname}`).toBe("https://accounts.google.com/o/oauth2/v2/auth");
  expect(Object.fromEntries(location.searchParams)).toEqual({ client_id: CLIENT, redirect_uri: `${ORIGIN}/apps/relay/google/callback`,
    response_type: "code", scope: `openid email ${SCOPES.join(" ")}`, access_type: "offline", prompt: "consent", state: saved.state,
    nonce: saved.nonce, code_challenge: await challenge(saved.verifier), code_challenge_method: "S256" });
  expect(response.headers.get("Set-Cookie")).toMatch(/; Path=\/apps\/relay\/google\/; HttpOnly; SameSite=Lax; Max-Age=600; Secure$/);
  expect(saved.person).toBe(ANA);
});

it("seals the sign-in in the person's own space and goes back to the page", async () => {
  const { cookie } = await begin();
  expect(await back(matthew, `code=c-1&state=${saved.state}`, cookie)).toBe("/apps/relay/?google=connected");
  expect(Object.fromEntries(sent[0].body)).toMatchObject({ grant_type: "authorization_code", code: "c-1", code_verifier: saved.verifier,
    redirect_uri: `${ORIGIN}/apps/relay/google/callback` });
  expect(rows("relay_google")).toMatchObject([{ email: "ana@gmail.example", scopes: SCOPES.join(" ") }]);
  expect(rows("relay_google", BEN)).toEqual([]);
  expect(await call(matthew, "GET", "google", undefined, GOOGLE_ENV)).toEqual({ status: 200,
    json: { available: true, connected: { email: "ana@gmail.example", scopes: SCOPES, connectedAt: NOW } } });
  expect((await call(ben, "GET", "google", undefined, GOOGLE_ENV)).json).toEqual({ available: true, connected: null });
});

it("keeps nothing when the person cancels at Google", async () => {
  const { cookie } = await begin();
  expect(await back(matthew, `error=access_denied&state=${saved.state}`, cookie)).toBe("/apps/relay/");
  expect(sent).toEqual([]);
  expect(rows("relay_google")).toEqual([]);
});

it("ends a sign-in missing a permission at Google, and keeps nothing", async () => {
  const { cookie } = await begin();
  tokens = async nonce => ({ id_token: await idToken(nonce), refresh_token: "1//refresh-ana", scope: `openid ${SCOPES.slice(1).join(" ")}` });
  expect(await back(matthew, `code=c-1&state=${saved.state}`, cookie)).toBe("/apps/relay/?google=missing");
  expect(sent.at(-1)).toEqual({ url: REVOKE_URL, body: new URLSearchParams({ token: "1//refresh-ana" }) });
  expect(rows("relay_google")).toEqual([]);
});

it("keeps nothing when Google's trade fails or leaves out the ID token, and no permission named is one missing", async () => {
  const { cookie } = await begin();
  const finish = () => back(matthew, `code=c-1&state=${saved.state}`, cookie);
  tokens = async () => new Response("down", { status: 500 });
  expect(await finish()).toBe("/apps/relay/?google=failed");
  tokens = async () => ({ refresh_token: "1//refresh-ana", scope: SCOPES.join(" ") });
  expect(await finish()).toBe("/apps/relay/?google=failed");
  tokens = async nonce => ({ id_token: await idToken(nonce), refresh_token: "1//refresh-ana" });
  expect(await finish()).toBe("/apps/relay/?google=missing");
  expect(rows("relay_google")).toEqual([]);
});

it("refuses a turned-off key, and a server with no spaces keeps nothing", async () => {
  expect((await page(lost, "connect"))!.status).toBe(403);
  const { cookie } = await begin();
  const finished = (await page(matthew, `callback?code=c-1&state=${saved.state}`, cookie, { ...GOOGLE_ENV, SPACES: undefined }))!;
  expect(finished.status).toBe(503);
  expect(rows("relay_google")).toEqual([]);
});

it("refuses a wrong state, another person's browser, and an ID token for another sign-in", async () => {
  const { cookie } = await begin();
  expect(await back(matthew, "code=c-1&state=forged", cookie)).toBe("/apps/relay/?google=failed");
  expect(await back(ben, `code=c-1&state=${saved.state}`, cookie)).toBe("/apps/relay/?google=failed");
  expect(await back(matthew, `code=c-1&state=${saved.state}`, "")).toBe("/apps/relay/?google=failed");
  tokens = async () => ({ id_token: await idToken("another-nonce"), refresh_token: "1//refresh-ana", scope: SCOPES.join(" ") });
  expect(await back(matthew, `code=c-1&state=${saved.state}`, cookie)).toBe("/apps/relay/?google=failed");
  expect(rows("relay_google")).toEqual([]);
  expect(rows("relay_google", BEN)).toEqual([]);
});

it("lets only a person signed in on the page connect: never a device key, and no one on a server with no Google client", async () => {
  expect((await page(phone, "connect"))!.status).toBe(403);
  expect((await page(null, "connect"))!.headers.get("Location")).toBe("/apps/relay/");
  expect((await page(matthew, "connect", "", {}))!.status).toBe(503);
  expect((await page(matthew, "other"))!.status).toBe(404);
  expect(await googleConnect(request(matthew, "GET", `${ORIGIN}/apps/relay/api/google`), env() as never, null)).toBeNull();
  expect((await call(matthew, "GET", "google")).json).toEqual({ available: false, connected: null });
  expect((await call(phone, "GET", "google", undefined, GOOGLE_ENV)).status).toBe(403);
});

it("disconnects: ends the sign-in at Google and deletes it, from the page only", async () => {
  const { cookie } = await begin();
  await back(matthew, `code=c-1&state=${saved.state}`, cookie);
  expect((await call(ben, "POST", "google-disconnect", {}, GOOGLE_ENV)).json).toEqual({ disconnected: false });
  expect(rows("relay_google")).toHaveLength(1);
  expect(await call(matthew, "POST", "google-disconnect", {}, GOOGLE_ENV)).toEqual({ status: 200, json: { disconnected: true } });
  expect(sent.at(-1)).toEqual({ url: REVOKE_URL, body: new URLSearchParams({ token: "1//refresh-ana" }) });
  expect(rows("relay_google")).toEqual([]);
});
