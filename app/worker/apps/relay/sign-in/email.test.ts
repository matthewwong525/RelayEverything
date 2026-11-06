import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { body } from "../../../../tests/body";
import { database } from "../../../../tests/employee-access/connections";
import { callerOf } from "../caller";
import { hashToken } from "../people";
import { signIn, type SignInEnv } from "./index";

const ORIGIN = "https://app.example.com";
const NOW = Date.UTC(2026, 10, 6, 12);
let db: ReturnType<typeof database>;
const mail = { sent: [] as { to: string; subject: string; text: string; from: string }[],
  send: vi.fn(async (message: { to: string; subject: string; text: string; from: string }) => { mail.sent.push(message); return { messageId: "m" }; }) };
let allowed: (key: string) => boolean;
const limiter = { limit: vi.fn(async ({ key }: { key: string }) => ({ success: allowed(key) })) };

const env = (more: object = {}) => ({ DB: db.DB, RELAY_EMAIL: mail, RELAY_SIGN_IN_FROM: "sign-in@relayeverything.com",
  RELAY_SIGN_IN_LIMIT: limiter, RELAY_SIGN_UP: "open", ...more }) as unknown as SignInEnv;
const post = (path: string, body: unknown, headers: Record<string, string> = {}, origin = ORIGIN) =>
  new Request(`${origin}/apps/relay/sign-in/${path}`, { method: "POST", body: JSON.stringify(body),
    headers: { Origin: origin, "content-type": "application/json", ...headers } });
const send = async (request: Request, more?: object) => (await signIn(request, env(more), null))!;
const lastCode = () => /\d{6}/.exec(mail.sent.at(-1)!.text)![0];
const count = (table: string) => (db.sql.prepare(`SELECT count(*) AS n FROM ${table}`).get() as { n: number }).n;
const sessionOf = (response: Response) => response.headers.get("Set-Cookie")!.split(";")[0];

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
  db = database();
  mail.sent = [];
  allowed = () => true;
});
afterEach(() => { vi.useRealTimers(); });

async function signInByCode(email = "ana@example.com", more?: object) {
  await send(post("email", { email }), more);
  return send(post("code", { email, code: lastCode() }), more);
}

describe("the sign-in's addresses", () => {
  it("leaves other addresses alone, and answers 404 for an unknown sign-in address", async () => {
    expect(await signIn(new Request(`${ORIGIN}/apps/relay/api/notes`), env(), null)).toBeNull();
    expect((await send(new Request(`${ORIGIN}/apps/relay/sign-in/nothing`))).status).toBe(404);
  });

  it("refuses a POST from another site, or with no Origin", async () => {
    expect((await send(post("email", { email: "ana@example.com" }, { Origin: "https://evil.example.com" }))).status).toBe(403);
    const bare = new Request(`${ORIGIN}/apps/relay/sign-in/out`, { method: "POST" });
    expect((await send(bare)).status).toBe(403);
    expect(mail.sent).toEqual([]);
  });

  it("lists only the ways in the server has set up", async () => {
    const methods = async (more: object) => (await send(new Request(`${ORIGIN}/apps/relay/sign-in/methods`), more)).json();
    expect(await methods({ RELAY_EMAIL: undefined, RELAY_SIGN_UP: undefined, RELAY_APPLE_TEAM_ID: "T" }))
      .toEqual({ email: false, apple: false, google: false, signUp: false });
    expect(await methods({ RELAY_SIGN_IN_FROM: undefined, RELAY_GOOGLE_CLIENT_ID: "g" })).toEqual({ email: false, apple: false, google: false, signUp: true });
    expect(await methods({ RELAY_APPLE_TEAM_ID: "T", RELAY_APPLE_SERVICES_ID: "S", RELAY_APPLE_SIGN_IN_KEY: "K", RELAY_APPLE_SIGN_IN_KEY_ID: "I",
      RELAY_GOOGLE_CLIENT_ID: "g", RELAY_GOOGLE_SIGN_IN_SECRET: "s" })).toEqual({ email: true, apple: true, google: true, signUp: true });
  });
});

describe("POST email", () => {
  it("emails a 6-digit code from the sign-in address and keeps only its fingerprint", async () => {
    const response = await send(post("email", { email: " Ana@Example.com " }));
    expect(await response.json()).toEqual({ sent: true });
    expect(mail.sent[0]).toMatchObject({ from: "sign-in@relayeverything.com", to: "ana@example.com" });
    expect(mail.sent[0].subject).toContain("Relay Everything");
    const row = db.sql.prepare("SELECT * FROM relay_sign_in_codes").get() as { code_sha256: string; expires_at: number };
    expect(row.code_sha256).toBe(await hashToken(`ana@example.com:${lastCode()}`));
    expect(row.expires_at).toBe(NOW + 10 * 60_000);
    expect(limiter.limit).toHaveBeenCalledWith({ key: "email:ana@example.com" });
    expect(limiter.limit).toHaveBeenCalledWith({ key: "ip:unknown" });
  });

  it("refuses a bad address, a server with no sender, and a caller over the limit", async () => {
    expect((await send(post("email", { email: "not an email" }))).status).toBe(400);
    const broken = new Request(`${ORIGIN}/apps/relay/sign-in/email`, { method: "POST", body: "{", headers: { Origin: ORIGIN } });
    expect((await send(broken)).status).toBe(400);
    expect((await send(post("email", { email: "ana@example.com" }), { RELAY_EMAIL: undefined })).status).toBe(503);
    allowed = key => key !== "ip:203.0.113.9";
    expect((await send(post("email", { email: "ana@example.com" }, { "CF-Connecting-IP": "203.0.113.9" }))).status).toBe(429);
    allowed = key => key !== "email:ana@example.com";
    expect((await send(post("email", { email: "ana@example.com" }))).status).toBe(429);
    expect((await send(post("email", { email: "ana@example.com" }), { RELAY_SIGN_IN_LIMIT: undefined })).status).toBe(200);
    expect(mail.sent).toHaveLength(1);
  });

  it("on a closed server, refuses a stranger and sends to the owner and to a person who has an account", async () => {
    const closed = { RELAY_SIGN_UP: undefined, WONG_OWNER_EMAIL: "owner@example.com" };
    const stranger = await send(post("email", { email: "stranger@example.com" }), closed);
    expect(stranger.status).toBe(403);
    expect((await body(stranger)).error.message).toContain("does not take new accounts");
    expect((await send(post("email", { email: "Owner@example.com" }), closed)).status).toBe(200);
    db.sql.prepare("INSERT INTO relay_people VALUES ('p-ben', 'ben@example.com', 1)").run();
    expect((await send(post("email", { email: "ben@example.com" }), closed)).status).toBe(200);
    expect((await send(post("email", { email: "stranger@example.com" }), { RELAY_SIGN_UP: undefined })).status).toBe(403);
  });
});

describe("POST code", () => {
  it("signs in with the right code: a new person, a session kept 30 days, and a cookie only the server reads", async () => {
    const response = await signInByCode();
    expect(await response.json()).toEqual({ ok: true });
    const cookie = response.headers.get("Set-Cookie")!;
    expect(cookie).toMatch(/^__Host-relay_session=[A-Za-z0-9_-]{43}; Path=\/; HttpOnly; SameSite=Lax; Max-Age=2592000; Secure$/);
    const person = db.sql.prepare("SELECT * FROM relay_people").get() as { id: string; email: string };
    expect(person.email).toBe("ana@example.com");
    const session = db.sql.prepare("SELECT * FROM relay_sessions").get() as { token_sha256: string; expires_at: number };
    expect(session.token_sha256).toBe(await hashToken(sessionOf(response).split("=")[1]));
    expect(session.expires_at).toBe(NOW + 30 * 86_400_000);
    const caller = await callerOf(new Request(`${ORIGIN}/apps/relay/api/timeline`, { headers: { Cookie: sessionOf(response) } }), env(), null);
    expect(caller).toMatchObject({ kind: "session", personId: person.id, email: "ana@example.com" });
    expect(count("relay_sign_in_codes")).toBe(0);
  });

  it("refuses a wrong code and counts the try", async () => {
    await send(post("email", { email: "ana@example.com" }));
    const wrong = String((Number(lastCode()) + 1) % 1_000_000).padStart(6, "0");
    const response = await send(post("code", { email: "ana@example.com", code: wrong }));
    expect(response.status).toBe(400);
    expect((await body(response)).error.message).toBe("This code is wrong or old. Ask for a new one.");
    expect(db.sql.prepare("SELECT tries FROM relay_sign_in_codes").get()).toEqual({ tries: 1 });
    expect(count("relay_sessions")).toBe(0);
  });

  it("ends the code after 5 wrong tries, so the right one fails after", async () => {
    await send(post("email", { email: "ana@example.com" }));
    const right = lastCode();
    const wrong = String((Number(right) + 1) % 1_000_000).padStart(6, "0");
    for (let i = 0; i < 5; i++) expect((await send(post("code", { email: "ana@example.com", code: wrong }))).status).toBe(400);
    expect(count("relay_sign_in_codes")).toBe(0);
    expect((await send(post("code", { email: "ana@example.com", code: right }))).status).toBe(400);
    expect(count("relay_sessions")).toBe(0);
  });

  it("counts each of many wrong tries at once, so the right code after the fifth is refused", async () => {
    await send(post("email", { email: "ana@example.com" }));
    const right = lastCode();
    const wrong = String((Number(right) + 1) % 1_000_000).padStart(6, "0");
    const all = await Promise.all(Array.from({ length: 8 }, () => send(post("code", { email: "ana@example.com", code: wrong }))));
    expect(all.map(response => response.status)).toEqual(Array(8).fill(400));
    expect((await send(post("code", { email: "ana@example.com", code: right }))).status).toBe(400);
    expect(count("relay_sessions")).toBe(0);
  });

  it("takes the right code as the fifth try, and refuses it once 5 tries are used", async () => {
    await send(post("email", { email: "ana@example.com" }));
    const right = lastCode();
    const wrong = String((Number(right) + 1) % 1_000_000).padStart(6, "0");
    for (let i = 0; i < 4; i++) await send(post("code", { email: "ana@example.com", code: wrong }));
    expect((await send(post("code", { email: "ana@example.com", code: right }))).status).toBe(200);
    // A code row with its 5 tries used, as a call that lost a race leaves it, opens nothing.
    db.sql.prepare("INSERT INTO relay_sign_in_codes VALUES (?, ?, ?, 5)").run("ben@example.com",
      await hashToken("ben@example.com:123456"), NOW + 60_000);
    expect((await send(post("code", { email: "ben@example.com", code: "123456" }))).status).toBe(400);
    expect(count("relay_sessions")).toBe(1);
  });

  it("refuses an expired code", async () => {
    await send(post("email", { email: "ana@example.com" }));
    vi.setSystemTime(NOW + 10 * 60_000);
    expect((await send(post("code", { email: "ana@example.com", code: lastCode() }))).status).toBe(400);
    expect(count("relay_sessions")).toBe(0);
  });

  it("refuses a replayed code, even two calls at once", async () => {
    await send(post("email", { email: "ana@example.com" }));
    const code = lastCode();
    const both = await Promise.all([send(post("code", { email: "ana@example.com", code })), send(post("code", { email: "ana@example.com", code }))]);
    expect(both.map(response => response.status).sort()).toEqual([200, 400]);
    expect((await send(post("code", { email: "ana@example.com", code }))).status).toBe(400);
    expect(count("relay_sessions")).toBe(1);
  });

  it("refuses the right code when another call used it between the try count and the delete", async () => {
    await send(post("email", { email: "ana@example.com" }));
    // The other call takes the code just before this call's delete runs.
    const session = db.DB.withSession("first-primary");
    const DB = { withSession: () => ({ prepare: (sql: string) => {
      if (sql.includes("code_sha256 = ? RETURNING")) db.sql.prepare("DELETE FROM relay_sign_in_codes").run();
      return session.prepare(sql);
    } }) };
    expect((await send(post("code", { email: "ana@example.com", code: lastCode() }), { DB })).status).toBe(400);
    expect(count("relay_sessions")).toBe(0);
  });

  it("refuses a bad body, a caller over the limit, and a code for an email that may no longer join", async () => {
    expect((await send(post("code", { email: "ana@example.com", code: "12345" }))).status).toBe(400);
    allowed = () => false;
    expect((await send(post("code", { email: "ana@example.com", code: "123456" }))).status).toBe(429);
    allowed = () => true;
    db.sql.prepare("INSERT INTO relay_sign_in_codes VALUES (?, ?, ?, 0)").run("stranger@example.com",
      await hashToken("stranger@example.com:123456"), NOW + 60_000);
    expect((await send(post("code", { email: "stranger@example.com", code: "123456" }), { RELAY_SIGN_UP: undefined })).status).toBe(403);
    expect(count("relay_people")).toBe(0);
  });
});

describe("POST out", () => {
  it("ends the session, so its old cookie opens nothing", async () => {
    const cookie = sessionOf(await signInByCode());
    const out = await send(post("out", {}, { Cookie: cookie }));
    expect(await out.json()).toEqual({ ok: true });
    expect(out.headers.get("Set-Cookie")).toBe("__Host-relay_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0; Secure");
    expect(count("relay_sessions")).toBe(0);
    expect(await callerOf(new Request(`${ORIGIN}/apps/relay/api/timeline`, { headers: { Cookie: cookie } }), env(), null)).toBeNull();
  });

  it("answers with no cookie too, and uses the plain cookie name on a local http run", async () => {
    const local = "http://localhost:8787";
    const out = await send(post("out", {}, {}, local));
    expect(out.headers.get("Set-Cookie")).toBe("relay_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0");
    await send(post("email", { email: "ana@example.com" }, {}, local));
    const signedIn = await send(post("code", { email: "ana@example.com", code: lastCode() }, {}, local));
    expect(signedIn.headers.get("Set-Cookie")).toMatch(/^relay_session=[^;]+; Path=\/; HttpOnly; SameSite=Lax; Max-Age=2592000$/);
  });
});
