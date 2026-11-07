import { expect, it, vi } from "vitest";
import { ANA, BEN, call, directoryDb, env, matthew, NOW, owner, phone as phoneKeyWho, request, rows, type Who } from "../../../../tests/relay";
import { body } from "../../../../tests/body";
import { relayGate } from "../caller";
import { hashToken } from "../people";
import { signIn } from "./index";

const ORIGIN = "https://relay.example.com";
const VERIFIER = "v".repeat(43);
const CHALLENGE = "7w_YNF9DSfIdPf_pRjSq646_kPr-2-o9NAl16JGghdM";
const identityOf = (who: Who) => who && "kind" in who ? who : null;

async function send(who: Who, method: string, path: string, init: RequestInit = {}, more: object = {}) {
  return (await signIn(request(who, method, `${ORIGIN}/apps/relay/sign-in/${path}`, init), env(more), identityOf(who)))!;
}
const open = (who: Who, query = `?challenge=${CHALLENGE}&name=Ana%27s%20iPhone`) => send(who, "GET", `phone${query}`);
const confirm = (who: Who, fields: Record<string, string>, headers: Record<string, string> = {}) =>
  send(who, "POST", "phone", { body: new URLSearchParams(fields), headers });
const trade = (input: object, more?: object) =>
  send(null, "POST", "phone/key", { headers: { "content-type": "application/json", Origin: "null" }, body: JSON.stringify(input) }, more);

/** Ana confirms the phone, and the app gets back its code. */
async function codeFor(who: Who = matthew, name = "Ana's iPhone") {
  const response = await confirm(who, { challenge: CHALLENGE, name, choice: "connect" });
  expect(response.status).toBe(302);
  const back = response.headers.get("Location")!;
  expect(back).toMatch(/^relayeverything:\/\/connected\?code=[A-Za-z0-9_-]{43}$/);
  return new URL(back).searchParams.get("code")!;
}

it("asks a signed-in person to connect this phone by its name, and sends one signed out to sign in first", async () => {
  const page = await open(matthew);
  expect(page.status).toBe(200);
  const html = await page.text();
  expect(html).toContain("Connect this phone?");
  expect(html).toContain('value="Ana&#39;s iPhone"');
  expect(html).toContain(`value="${CHALLENGE}"`);
  expect((await open(owner, `?challenge=${CHALLENGE}`)).status).toBe(200);
  const out = await open(null);
  expect(out.headers.get("Location")).toBe(`/apps/relay/?next=${encodeURIComponent(`/apps/relay/sign-in/phone?challenge=${CHALLENGE}&name=Ana%27s%20iPhone`)}`);
  expect((await open(matthew, "?challenge=short")).status).toBe(400);
  expect((await open(phoneKeyWho)).status).toBe(403);
});

it("makes the phone its own key from a code and its secret, once, and the key only sends to Ana's space", async () => {
  const code = await codeFor();
  const stored = directoryDb.sql.prepare("SELECT * FROM relay_phone_codes").get() as Record<string, unknown>;
  expect(stored).toEqual({ code_sha256: await hashToken(code), person_id: ANA, name: "Ana's iPhone", challenge: CHALLENGE,
    expires_at: NOW + 5 * 60_000 });
  const answer = await trade({ code, verifier: VERIFIER });
  expect(answer.status).toBe(200);
  const { server, key } = await answer.json() as { server: string; key: string };
  expect([server, key]).toEqual([ORIGIN, expect.stringMatching(/^rek_[A-Za-z0-9_-]{43}$/)]);
  expect(directoryDb.sql.prepare("SELECT count(*) AS n FROM relay_phone_codes").get()).toEqual({ n: 0 });
  // The page lists the phone, with no key in the list.
  const listed = (await call(matthew, "GET", "devices")).json.devices.find(device => String(device.name) === "Ana's iPhone");
  expect(listed).toMatchObject({ reaches: "phone", revokedAt: null });
  expect(JSON.stringify(directoryDb.sql.prepare("SELECT * FROM relay_keys").all())).not.toContain(key);
  // The key checks itself, sends a note to Ana's space, and reads nothing.
  expect(await call({ bearer: key }, "GET", "key")).toEqual({ status: 200, json: { device: "Ana's iPhone" } });
  const note = { clientId: "phone-note-1", text: "Ask about the ring's charger", createdAt: NOW };
  expect((await call({ bearer: key }, "POST", "notes", note)).status).toBe(200);
  expect(rows("relay_notes").map(row => row.text)).toContain("Ask about the ring's charger");
  expect(rows("relay_notes", BEN)).toEqual([]);
  for (const path of ["/apps/relay/api/timeline", "/apps/relay/api/devices"]) {
    const refused = await relayGate(request({ bearer: key }, "GET", `${ORIGIN}${path}`), env(), null, path);
    expect(refused?.status, path).toBe(403);
  }
  // Used once: a second trade makes no key.
  expect((await body(await trade({ code, verifier: VERIFIER }))).error.message).toMatch(/used already, or is too old/);
  expect(directoryDb.sql.prepare("SELECT count(*) AS n FROM relay_keys WHERE person_id = ?").get(ANA)).toEqual({ n: 5 });
});

it("refuses a code after 5 minutes, and a wrong secret, which also ends the code", async () => {
  const late = await codeFor();
  vi.setSystemTime(NOW + 5 * 60_000 + 1);
  expect((await trade({ code: late, verifier: VERIFIER })).status).toBe(400);
  vi.setSystemTime(NOW);
  const code = await codeFor();
  expect((await trade({ code, verifier: "w".repeat(43) })).status).toBe(400);
  expect((await trade({ code, verifier: VERIFIER })).status).toBe(400);
  expect((await trade({ code: "x" })).status).toBe(400);
  expect(directoryDb.sql.prepare("SELECT count(*) AS n FROM relay_keys WHERE person_id = ?").get(ANA)).toEqual({ n: 4 });
});

it("takes Connect only from the Relay Everything page, only from a person, and tells the app on Cancel", async () => {
  const fields = { challenge: CHALLENGE, name: "Ana's iPhone", choice: "connect" };
  expect((await confirm(matthew, fields, { Origin: "https://evil.example" })).status).toBe(403);
  expect((await confirm(null, fields)).status).toBe(403);
  expect((await confirm(phoneKeyWho, fields)).status).toBe(403);
  expect((await confirm(matthew, { ...fields, challenge: "short" })).status).toBe(400);
  const cancel = await confirm(matthew, { ...fields, choice: "cancel" });
  expect(cancel.headers.get("Location")).toBe("relayeverything://connected?error=cancelled");
  expect(directoryDb.sql.prepare("SELECT count(*) AS n FROM relay_phone_codes").get()).toEqual({ n: 0 });
  // An empty name gets a plain one.
  await codeFor(matthew, " ");
  expect(directoryDb.sql.prepare("SELECT name FROM relay_phone_codes").get()).toEqual({ name: "Phone" });
});

it("limits trades by address, and answers 503 on a server with no spaces", async () => {
  const limit = { limit: vi.fn(async () => ({ success: false })) };
  expect((await trade({ code: "x", verifier: VERIFIER }, { RELAY_SIGN_IN_LIMIT: limit })).status).toBe(429);
  expect(limit.limit).toHaveBeenCalledWith({ key: "ip:unknown" });
  const code = await codeFor();
  expect((await trade({ code, verifier: VERIFIER }, { SPACES: undefined })).status).toBe(503);
});

it("refuses an unknown key, a missing challenge, and a body that is not a form or JSON", async () => {
  const stranger: Who = { bearer: `rek_${"x".repeat(43)}` };
  expect((await open(stranger)).status).toBe(403);
  expect((await confirm(stranger, { challenge: CHALLENGE, choice: "connect" })).status).toBe(403);
  expect((await open(matthew, "")).status).toBe(400);
  expect((await confirm(matthew, { choice: "connect" })).status).toBe(400);
  const notForm = await send(matthew, "POST", "phone", { body: "{", headers: { "content-type": "multipart/form-data; boundary=x" } });
  expect(notForm.headers.get("Location")).toBe("relayeverything://connected?error=cancelled");
  const notJson = await send(null, "POST", "phone/key", { headers: { "content-type": "application/json" }, body: "{" });
  expect(notJson.status).toBe(400);
  expect((await trade({ code: "x".repeat(101), verifier: VERIFIER })).status).toBe(400);
  expect((await trade({ code: 1, verifier: 2 })).status).toBe(400);
});
