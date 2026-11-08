import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { database } from "../../../../tests/employee-access/connections";
import { signIn, type SignInEnv } from "./index";
import { challenge } from "./jwt";

const ORIGIN = "https://app.example.com";
const NOW = Date.UTC(2026, 10, 6, 12);
const GOOGLE = "google-client.example.com";
const SERVICES = "com.example.signin";
const FAILED = "/apps/relay/?signIn=failed";
const encoder = new TextEncoder();
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
const part = (value: unknown) => b64(encoder.encode(JSON.stringify(value)));

const claimed = vi.hoisted(() => vi.fn(async (_person: { email: string }) => {}));
vi.mock("../inbox/held", () => ({ claimOnSignIn: () => claimed }));

const RSA = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
let good: CryptoKeyPair, forged: CryptoKeyPair, apple: CryptoKeyPair, pem: string, jwk: JsonWebKey & { kid: string };
beforeAll(async () => {
  good = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]) as CryptoKeyPair;
  forged = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]) as CryptoKeyPair;
  apple = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", apple.privateKey) as ArrayBuffer);
  // A .p8 file's shape, with its line breaks pasted as \n; the label is joined so no key-shaped text sits in git.
  const label = ["PRIVATE", "KEY"].join(" ");
  pem = `-----BEGIN ${label}-----\\n${btoa(String.fromCharCode(...der))}\\n-----END ${label}-----`;
  jwk = { ...await crypto.subtle.exportKey("jwk", good.publicKey) as JsonWebKey, kid: "k1", alg: "RS256" };
});

/** An ID token signed by `key`, with these claims over a good default. */
async function idToken(claims: Record<string, unknown>, { key = good.privateKey, header = { alg: "RS256", kid: "k1" } } = {}) {
  const data = `${part(header)}.${part(claims)}`;
  return `${data}.${b64(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(data))))}`;
}

let db: ReturnType<typeof database>;
let token: () => Promise<string | null>;
let tokenStatus: number;
const requests: { url: string; body: URLSearchParams }[] = [];
const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
  if (url.endsWith("/certs") || url.endsWith("/keys")) return Response.json({ keys: [jwk] });
  requests.push({ url, body: new URLSearchParams(String(init!.body)) });
  const value = await token();
  return Response.json(value === null ? {} : { id_token: value }, { status: tokenStatus });
});

const env = (more: object = {}) => ({ DB: db.DB, RELAY_SIGN_UP: "open", RELAY_GOOGLE_CLIENT_ID: GOOGLE, RELAY_GOOGLE_SIGN_IN_SECRET: "google-secret",
  RELAY_APPLE_TEAM_ID: "TEAM123456", RELAY_APPLE_SERVICES_ID: SERVICES, RELAY_APPLE_SIGN_IN_KEY_ID: "KEY1234567", RELAY_APPLE_SIGN_IN_KEY: pem,
  ...more }) as unknown as SignInEnv;
const send = async (request: Request, more?: object) => (await signIn(request, env(more), null))!;
const count = (table: string) => (db.sql.prepare(`SELECT count(*) AS n FROM ${table}`).get() as { n: number }).n;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
  vi.stubGlobal("fetch", fetchMock);
  db = database();
  requests.length = 0;
  tokenStatus = 200;
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

/** Starts a sign-in: the provider's address, its query and the state cookie. */
async function begin(provider: "apple" | "google", query = "", origin = ORIGIN) {
  const response = await send(new Request(`${origin}/apps/relay/sign-in/${provider}${query}`));
  const location = new URL(response.headers.get("Location")!);
  const cookie = response.headers.get("Set-Cookie")!;
  const saved = JSON.parse(atob(cookie.split(";")[0].slice("relay_oauth=".length))) as { state: string; nonce: string; verifier: string };
  return { response, location, cookie, saved, params: location.searchParams };
}

const claimsFor = (audience: string, nonce: string, more: object = {}) => ({ iss: "https://accounts.google.com", aud: audience, nonce,
  exp: NOW / 1000 + 600, sub: "google-sub-ana", email: "ana@example.com", email_verified: true, ...more });

async function googleBack(state: string, cookie: string, origin = ORIGIN) {
  return send(new Request(`${origin}/apps/relay/sign-in/google/callback?code=c-1&state=${state}`, { headers: { Cookie: cookie.split(";")[0] } }));
}

describe("Sign in with Google", () => {
  it("sends the browser to Google with PKCE, state and nonce, and keeps them in a short cookie", async () => {
    const { response, location, cookie, saved, params } = await begin("google", "?next=/apps/relay/sign-in/connect%3Fstate%3Dx");
    expect(response.status).toBe(302);
    expect(location.origin + location.pathname).toBe("https://accounts.google.com/o/oauth2/v2/auth");
    expect(Object.fromEntries(params)).toEqual({ client_id: GOOGLE, redirect_uri: `${ORIGIN}/apps/relay/sign-in/google/callback`,
      state: saved.state, nonce: saved.nonce, scope: "openid email", response_type: "code",
      code_challenge: await challenge(saved.verifier), code_challenge_method: "S256" });
    expect(cookie).toMatch(/; Path=\/apps\/relay\/sign-in\/; HttpOnly; Max-Age=600; SameSite=None; Secure$/);
  });

  it("signs in a checked email, and goes on to the page asked for", async () => {
    const { cookie, saved } = await begin("google", "?next=/apps/relay/sign-in/connect%3Fstate%3Dx");
    token = () => idToken(claimsFor(GOOGLE, saved.nonce));
    const response = await googleBack(saved.state, cookie);
    expect(response.headers.get("Location")).toBe("/apps/relay/sign-in/connect?state=x");
    const cookies = response.headers.getSetCookie();
    expect(cookies[0]).toMatch(/^__Host-relay_session=/);
    expect(cookies[1]).toMatch(/^relay_oauth=; .*Max-Age=0/);
    expect(Object.fromEntries(requests[0].body)).toEqual({ grant_type: "authorization_code", code: "c-1",
      redirect_uri: `${ORIGIN}/apps/relay/sign-in/google/callback`, client_id: GOOGLE, client_secret: "google-secret", code_verifier: saved.verifier });
    expect(db.sql.prepare("SELECT provider, subject FROM relay_logins").all()).toEqual([{ provider: "google", subject: "google-sub-ana" }]);
    expect(count("relay_sessions")).toBe(1);
  });

  it("claims kept mail for the signed-in email", async () => {
    const { cookie, saved } = await begin("google");
    token = () => idToken(claimsFor(GOOGLE, saved.nonce));
    await googleBack(saved.state, cookie);
    expect(claimed).toHaveBeenLastCalledWith(expect.objectContaining({ email: "ana@example.com" }));
  });

  it("keeps a linked login's person when the email changes, and sends an unsafe next to the page", async () => {
    let { cookie, saved } = await begin("google", "?next=https://evil.example.com/");
    token = () => idToken(claimsFor(GOOGLE, saved.nonce));
    expect((await googleBack(saved.state, cookie)).headers.get("Location")).toBe("/apps/relay/");
    ({ cookie, saved } = await begin("google"));
    token = () => idToken(claimsFor(GOOGLE, saved.nonce, { email: "ana.new@example.com" }));
    expect((await googleBack(saved.state, cookie)).status).toBe(302);
    expect(db.sql.prepare("SELECT email FROM relay_people").all()).toEqual([{ email: "ana@example.com" }]);
    expect(count("relay_sessions")).toBe(2);
  });

  const refusals: [string, (nonce: string) => Promise<string | null>][] = [
    ["a forged ID token", nonce => idToken(claimsFor(GOOGLE, nonce), { key: forged.privateKey })],
    ["an unverified email", nonce => idToken(claimsFor(GOOGLE, nonce, { email_verified: false }))],
    ["another issuer", nonce => idToken(claimsFor(GOOGLE, nonce, { iss: "https://evil.example.com" }))],
    ["another client", nonce => idToken(claimsFor("other-client", nonce))],
    ["another sign-in's nonce", () => idToken(claimsFor(GOOGLE, "old-nonce"))],
    ["an expired token", nonce => idToken(claimsFor(GOOGLE, nonce, { exp: NOW / 1000 - 1 }))],
    ["no expiry", nonce => idToken(claimsFor(GOOGLE, nonce, { exp: undefined }))],
    ["no subject", nonce => idToken(claimsFor(GOOGLE, nonce, { sub: 7 }))],
    ["no email", nonce => idToken(claimsFor(GOOGLE, nonce, { email: undefined }))],
    ["an unknown signing key", nonce => idToken(claimsFor(GOOGLE, nonce), { header: { alg: "RS256", kid: "k9" } })],
    ["another algorithm", nonce => idToken(claimsFor(GOOGLE, nonce), { header: { alg: "HS256", kid: "k1" } })],
    ["a token with no signature", async () => `${part({ alg: "RS256", kid: "k1" })}.${part({})}`],
    ["a token that is not a JWT", async () => "not a token"],
    ["no ID token", async () => null],
  ];
  it.each(refusals)("refuses %s, and makes no session", async (_name, make) => {
    const { cookie, saved } = await begin("google");
    token = () => make(saved.nonce);
    expect((await googleBack(saved.state, cookie)).headers.get("Location")).toBe(FAILED);
    expect(count("relay_sessions")).toBe(0);
  });

  it("refuses a bad state, a missing or broken cookie, no code, and a failed exchange", async () => {
    const { cookie, saved } = await begin("google");
    token = () => idToken(claimsFor(GOOGLE, saved.nonce));
    expect((await googleBack("wrong-state", cookie)).headers.get("Location")).toBe(FAILED);
    expect((await send(new Request(`${ORIGIN}/apps/relay/sign-in/google/callback?code=c&state=${saved.state}`))).headers.get("Location")).toBe(FAILED);
    expect((await googleBack(saved.state, "relay_oauth=%%%")).headers.get("Location")).toBe(FAILED);
    const noCode = new Request(`${ORIGIN}/apps/relay/sign-in/google/callback?state=${saved.state}`, { headers: { Cookie: cookie.split(";")[0] } });
    expect((await send(noCode)).headers.get("Location")).toBe(FAILED);
    tokenStatus = 400;
    expect((await googleBack(saved.state, cookie)).headers.get("Location")).toBe(FAILED);
    tokenStatus = 200;
    token = () => Promise.reject(new Error("Google is down"));
    expect((await googleBack(saved.state, cookie)).headers.get("Location")).toBe(FAILED);
    expect(count("relay_sessions")).toBe(0);
  });

  it("refuses a stranger on a closed server, and a provider the server no longer has", async () => {
    const { cookie, saved } = await begin("google");
    token = () => idToken(claimsFor(GOOGLE, saved.nonce));
    const closed = await send(new Request(`${ORIGIN}/apps/relay/sign-in/google/callback?code=c&state=${saved.state}`,
      { headers: { Cookie: cookie.split(";")[0] } }), { RELAY_SIGN_UP: undefined });
    expect(closed.headers.get("Location")).toBe(FAILED);
    const gone = await send(new Request(`${ORIGIN}/apps/relay/sign-in/google/callback?code=c&state=${saved.state}`,
      { headers: { Cookie: cookie.split(";")[0] } }), { RELAY_GOOGLE_SIGN_IN_SECRET: undefined });
    expect(gone.headers.get("Location")).toBe(FAILED);
    expect(count("relay_people")).toBe(0);
    expect((await send(new Request(`${ORIGIN}/apps/relay/sign-in/google`), { RELAY_GOOGLE_CLIENT_ID: undefined })).status).toBe(503);
  });

  it("uses a Lax cookie with no Secure on a local http run", async () => {
    const { cookie } = await begin("google", "", "http://localhost:8787");
    expect(cookie).toMatch(/; Max-Age=600; SameSite=Lax$/);
  });
});

describe("Sign in with Apple", () => {
  const appleClaims = (nonce: string, more: object = {}) => ({ iss: "https://appleid.apple.com", aud: SERVICES, nonce, exp: NOW / 1000 + 600,
    sub: "apple-sub-ana", email: "ana@example.com", email_verified: "true", ...more });
  const back = (fields: Record<string, string | Blob>, cookie?: string) => {
    const form = new FormData();
    for (const [name, value] of Object.entries(fields)) form.set(name, value);
    return send(new Request(`${ORIGIN}/apps/relay/sign-in/apple/callback`, { method: "POST", body: form,
      headers: cookie ? { Cookie: cookie.split(";")[0] } : {} }));
  };

  it("asks for a form post, and signs in from Apple's cross-site POST with a client secret signed by the key", async () => {
    const { location, cookie, saved, params } = await begin("apple");
    expect(location.origin + location.pathname).toBe("https://appleid.apple.com/auth/authorize");
    expect(params.get("response_mode")).toBe("form_post");
    expect(params.get("scope")).toBe("name email");
    expect(params.has("code_challenge")).toBe(false);
    token = () => idToken(appleClaims(saved.nonce));
    const response = await back({ code: "a-1", state: saved.state, user: new Blob(["{}"]) }, cookie);
    expect(response.headers.get("Location")).toBe("/apps/relay/");
    expect(count("relay_sessions")).toBe(1);
    const { client_secret: secret, code_verifier: verifier } = Object.fromEntries(requests[0].body);
    expect(verifier).toBeUndefined();
    const [head, body, signature] = secret.split(".");
    expect(JSON.parse(atob(head))).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(JSON.parse(atob(body))).toEqual({ iss: "TEAM123456", iat: NOW / 1000, exp: NOW / 1000 + 300, aud: "https://appleid.apple.com", sub: SERVICES });
    const bytes = Uint8Array.from(atob(signature.replaceAll("-", "+").replaceAll("_", "/")), char => char.charCodeAt(0));
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, apple.publicKey, bytes, encoder.encode(`${head}.${body}`))).toBe(true);
  });

  it("refuses an unverified email, a Google answer at Apple's address, and a body that is not a form", async () => {
    const { cookie, saved } = await begin("apple");
    token = () => idToken(appleClaims(saved.nonce, { email_verified: "false" }));
    expect((await back({ code: "a-1", state: saved.state }, cookie)).headers.get("Location")).toBe(FAILED);
    const google = await begin("google");
    expect((await back({ code: "a-1", state: google.saved.state }, google.cookie)).headers.get("Location")).toBe(FAILED);
    const notForm = new Request(`${ORIGIN}/apps/relay/sign-in/apple/callback`, { method: "POST", body: "{}",
      headers: { "content-type": "application/json", Cookie: cookie.split(";")[0] } });
    expect((await send(notForm)).headers.get("Location")).toBe(FAILED);
    expect(count("relay_sessions")).toBe(0);
    expect((await send(new Request(`${ORIGIN}/apps/relay/sign-in/apple`), { RELAY_APPLE_SIGN_IN_KEY: undefined })).status).toBe(503);
  });
});
