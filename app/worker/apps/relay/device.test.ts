import { expect, it } from "vitest";
import { body } from "../../../tests/body";
import { fakeEnv } from "../../../tests/env";
import { ANA, ben, benPhone, call, checker, db, deviceKey, directoryDb, laptop, lost, makeKey, matthew, owner, ipad, phone, request, rows,
  type Who } from "../../../tests/relay";
import { apiKeyCaller, callerOf, cookie, reaches, relayGate, SESSION_COOKIE, sessionCookie } from "./caller";
import { hashToken } from "./people";

// The fingerprint of checker.id, "checker.access".
const CHECKER_SHA256 = "6a6814c5281a7635cb9d9f881d7feae9b0d6159c868666fad3ffa0a164f4d999";
const ORIGIN = "https://relay.example.com";
const ROUTES = ["attachments", "notes", "health", "nights", "locations", "stays", "calendar", "photos"].map(route => `/apps/relay/api/${route}`);
const KEY = "/apps/relay/api/key";
const CHATS = "/apps/relay/api/chats";
const SAVES = "/apps/relay/api/chat-saves";
const CONNECTIONS = "/apps/relay/api/connections";
const NOTES = "/apps/relay/api/notes";
const SEND_ONLY = "A device key can only send to Relay Everything.";
const NO_LIST = "This key is on no list of devices.";
const identityOf = (who: Who) => who && "kind" in who ? who : null;

/** The Worker's gate for `who` on an address: null lets the call go on, else the refusal's status and words. */
async function gate(who: Who, method: string, path: string, { bindings = {}, headers = {} }: { bindings?: object; headers?: Record<string, string> } = {}) {
  const env = fakeEnv({ DB: db.DB, RELAY_CHECKER_SHA256: CHECKER_SHA256, ...bindings });
  const response = await relayGate(request(who, method, `${ORIGIN}${path}`, { headers }), env, identityOf(who), path);
  return response && [response.status, (await body(response)).error.message];
}

it("lets a phone key send, check itself, sync, change and delete its notes, and nothing else", async () => {
  for (const path of ROUTES) expect(await gate(phone, "POST", path), path).toBeNull();
  expect(await gate(phone, "GET", KEY)).toBeNull();
  expect(await gate(phone, "PATCH", NOTES)).toBeNull();
  expect(await gate(phone, "DELETE", NOTES)).toBeNull();
  // Its reads: the names of its person's AI apps and webhooks, and notes, their files and recordings, by GET only.
  for (const path of [CONNECTIONS, NOTES, "/apps/relay/api/attachment", "/apps/relay/api/audio"]) expect(await gate(phone, "GET", path), path).toBeNull();
  expect(await gate(phone, "POST", CONNECTIONS)).toEqual([403, SEND_ONLY]);
  // A phone can't read health, places, the calendar, photos or chats, even on an address it sends to.
  for (const [method, path] of [...ROUTES.filter(route => route !== NOTES).map(route => ["GET", route]), ["POST", KEY],
    ["GET", "/apps/relay/api/timeline"], ["GET", "/apps/relay/api/summary"], ["POST", "/apps/relay/api/attachment"], ["POST", "/apps/relay/api/audio"], ["GET", "/apps/relay/api/devices"], ["POST", "/apps/relay/api/devices"],
    ["POST", "/apps/relay/api/account-delete"], ["POST", "/apps/relay/api/photos/delete"], ["GET", "/apps/relay/"], ["GET", "/apps/hello/api/greeting"], ["GET", "/api/health"], ["GET", "/"],
    ["POST", "/apps/relay/api/notes/x"], ["POST", "/apps/relay/api/pebble"], ["POST", CHATS], ["POST", SAVES], ["GET", CHATS], ["DELETE", ROUTES[2]], ["HEAD", KEY],
    ["PATCH", "/apps/relay/api/health"], ["PATCH", "/apps/relay/api/notes/x"], ["DELETE", "/apps/relay/api/chat"], ["DELETE", "/apps/relay/api/notes/x"]]) {
    expect(await gate(phone, method, path), `${method} ${path}`).toEqual([403, SEND_ONLY]);
  }
});

it("lets a chats key only send chats and saves, and check itself, and nothing else", async () => {
  for (const path of [CHATS, SAVES]) expect(await gate(laptop, "POST", path), path).toBeNull();
  expect(await gate(laptop, "GET", KEY)).toBeNull();
  for (const [method, path] of [["GET", CHATS], ["GET", "/apps/relay/api/chat"], ["DELETE", "/apps/relay/api/chat"], ["GET", SAVES], ["GET", CONNECTIONS],
    ...ROUTES.map(route => ["POST", route]), ["PATCH", NOTES], ["DELETE", NOTES], ["GET", NOTES], ["GET", "/apps/relay/api/attachment"], ["GET", "/apps/relay/api/devices"],
    ["GET", "/api/health"]]) {
    expect(await gate(laptop, method, path), `${method} ${path}`).toEqual([403, "A chat key can only send chats."]);
  }
  expect(reaches("chats", "PUT", CHATS)).toBe(false);
});

it("refuses a turned-off or unknown key everywhere, and leaves the other keys working", async () => {
  for (const path of [...ROUTES, KEY, "/api/health"]) {
    expect(await gate(lost, "POST", path), path).toEqual([403, "This device key is turned off."]);
    expect(await gate({ bearer: makeKey("nobody") }, "POST", path), path).toEqual([403, NO_LIST]);
  }
  expect(await gate(phone, "POST", ROUTES[1])).toBeNull();
  expect(await gate(benPhone, "POST", ROUTES[1])).toBeNull();
  expect(await gate(ipad, "POST", ROUTES[0])).toBeNull();
});

it("lets the checker through, and refuses every other service token everywhere", async () => {
  for (const path of ["/api/health", "/api/access/apps", ROUTES[0], KEY]) {
    expect(await gate(checker, "GET", path), path).toBeNull();
    // A staging phone's token after a staging reset is on no list: it is no checker, and owns nothing.
    expect(await gate(deviceKey("reset.access"), "GET", path), path).toEqual([403, NO_LIST]);
  }
  // With no checker named, the checker is one more unknown token.
  expect(await gate(checker, "GET", "/api/health", { bindings: { RELAY_CHECKER_SHA256: undefined } })).toEqual([403, NO_LIST]);
});

it("leaves a person's own pages to the usual checks, and lets no one in only as no one", async () => {
  for (const who of [matthew, ben, owner, null]) {
    expect(await gate(who, "GET", "/api/health")).toBeNull();
    expect(await gate(who, "GET", "/apps/relay/api/timeline")).toBeNull();
  }
  // A Bearer word that is no device key is no caller: the route then asks for a sign-in.
  expect(await gate({ bearer: "not-a-key" }, "POST", ROUTES[1])).toBeNull();
  expect((await call({ bearer: "not-a-key" }, "GET", "devices")).status).toBe(401);
});

it("takes a change by cookie only from the Relay Everything page itself", async () => {
  const path = "/apps/relay/api/devices";
  expect(await gate(matthew, "POST", path)).toBeNull();
  const refusal = [403, "This change must come from the Relay Everything page."];
  expect(await gate(matthew, "POST", path, { headers: { Origin: "https://evil.example" } })).toEqual(refusal);
  expect(await gate(matthew, "DELETE", "/apps/relay/api/chat", { headers: { Origin: "https://evil.example" } })).toEqual(refusal);
  const bare = new Request(`${ORIGIN}${path}`, { method: "POST", headers: { Cookie: `${SESSION_COOKIE}=ana-session-token` } });
  const missing = await relayGate(bare, fakeEnv({ DB: db.DB }), null, path);
  expect(missing?.status).toBe(403);
  // A read by cookie, and a change by Access, carry no risk from another site.
  for (const method of ["GET", "HEAD", "OPTIONS"]) {
    expect(await gate(matthew, method, path, { headers: { Origin: "https://evil.example" } }), method).toBeNull();
  }
  expect(await gate(owner, "POST", path, { headers: { Origin: "https://evil.example" } })).toBeNull();
});

it("answers 503 when the directory can't be read, and asks it only once per request", async () => {
  const broken = fakeEnv({ DB: { withSession: () => { throw new Error("D1 is down"); } } });
  const sent = request(phone, "POST", `${ORIGIN}${ROUTES[1]}`);
  const refused = await relayGate(sent, broken, null, ROUTES[1]);
  expect([refused?.status, (await body(refused!)).error]).toEqual([503, { code: "unavailable",
    message: "Relay Everything's accounts could not be read. Try again." }]);
  expect(callerOf(sent, broken, null)).toBe(callerOf(sent, broken, null));
});

it("reads the session cookie by its name, and uses the plain name on a local http run", async () => {
  const sent = (header: string) => new Request(ORIGIN, { headers: { Cookie: header } });
  expect(cookie(sent(`theme=dark; ${SESSION_COOKIE}=a=b`), SESSION_COOKIE)).toBe("a=b");
  expect(cookie(sent(`${SESSION_COOKIE}=`), SESSION_COOKIE)).toBeNull();
  expect(cookie(new Request(ORIGIN), SESSION_COOKIE)).toBeNull();
  expect(sessionCookie(new URL(ORIGIN))).toBe(SESSION_COOKIE);
  expect(sessionCookie(new URL("http://localhost:8787"))).toBe("relay_session");
});

it("makes an account from Access's email only for the server's owner, or while sign-up is open", async () => {
  const visitor = (email: string): Who => ({ ...owner, id: email, claims: { ...owner.claims, email } });
  const timeline = "/apps/relay/api/timeline";
  const none = [403, "This email has no Relay Everything account on this server."];
  expect(await gate(visitor("cy@example.com"), "GET", timeline)).toEqual(none);
  expect(await gate(visitor("cy@example.com"), "GET", timeline, { bindings: { WONG_OWNER_EMAIL: "ana@example.com" } })).toEqual(none);
  expect(await gate(visitor(" Cy@Example.com "), "GET", timeline, { bindings: { WONG_OWNER_EMAIL: "cy@example.com" } })).toBeNull();
  expect(await gate(visitor("dee@example.com"), "GET", timeline, { bindings: { RELAY_SIGN_UP: "open" } })).toBeNull();
  expect(directoryDb.sql.prepare("SELECT email FROM relay_people ORDER BY email").all().map(row => row.email))
    .toEqual(["ana@example.com", "ben@example.com", "cy@example.com", "dee@example.com"]);
  // Signed in again, the same person is found, not made twice.
  expect(await call(visitor("cy@example.com"), "GET", "account")).toEqual({ status: 200, json: { email: "cy@example.com" } });
});

it("lists a person's devices, newest last, with no key in the list, and not the Email device", async () => {
  db.sql.prepare(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches)
    VALUES ('d-mail', 'Email', 'inbox:email', '', 0, 'inbox')`).run();
  const { status, json } = await call(matthew, "GET", "devices");
  expect(status).toBe(200);
  expect(json.devices.map(device => [device.id, device.reaches, device.revokedAt])).toEqual([["d-ipad", "phone", null],
    ["d-laptop", "chats", null], ["d-lost", "phone", expect.any(Number)], ["d-phone", "phone", null]]);
  expect(JSON.stringify(json)).not.toContain("rek_");
  expect((await call(ben, "GET", "devices")).json.devices.map(device => device.id)).toEqual(["d-ben"]);
});

it("shows a new key once, keeps only its SHA-256, and the key works at once", async () => {
  const { status, json } = await call(matthew, "POST", "devices", { name: " Kitchen tablet ", reaches: "phone" });
  expect(status).toBe(200);
  const made = json as unknown as { id: string; key: string; qr: string };
  expect(json).toEqual({ id: expect.any(String), name: "Kitchen tablet", reaches: "phone", key: expect.stringMatching(/^rek_[A-Za-z0-9_-]{43}$/),
    qr: expect.any(String), api: null });
  expect(JSON.parse(made.qr)).toEqual({ relay: 1, server: ORIGIN, key: made.key });
  const stored = directoryDb.sql.prepare("SELECT * FROM relay_keys WHERE device_id = ?").all(made.id);
  expect(stored).toEqual([{ key_sha256: await hashToken(made.key), person_id: ANA, device_id: made.id, reaches: "phone", created_at: expect.any(Number),
    revoked_at: null }]);
  expect(JSON.stringify(directoryDb.sql.prepare("SELECT * FROM relay_keys").all())).not.toContain(made.key);
  // No signing secret is made or kept: the space has no table for one.
  expect(db.sql.prepare("SELECT name FROM sqlite_master WHERE name = 'relay_device_secrets'").all()).toEqual([]);
  expect(await call({ bearer: made.key }, "GET", "key")).toEqual({ status: 200, json: { device: "Kitchen tablet" } });
  expect(await gate({ bearer: made.key }, "POST", ROUTES[1])).toBeNull();
  // The list never shows the key again.
  expect(JSON.stringify((await call(matthew, "GET", "devices")).json)).not.toContain(made.key);
});

it("lets a chats key send only chats", async () => {
  const { json } = await call(matthew, "POST", "devices", { name: "Work laptop", reaches: "chats" });
  expect(Object.keys(json).sort()).toEqual(["api", "id", "key", "name", "qr", "reaches"]);
  expect(await gate({ bearer: String(json.key) }, "POST", CHATS)).toBeNull();
  expect(await gate({ bearer: String(json.key) }, "POST", ROUTES[1])).toEqual([403, "A chat key can only send chats."]);
});

it("gives an API key the web API's address, and lets it reach only that and its own name on this server", async () => {
  const { json } = await call(matthew, "POST", "devices", { name: "Backup script", reaches: "api" },
    { RELAY_MCP_CALLBACK: "https://relay-mcp.example.com/callback" });
  expect(json).toMatchObject({ reaches: "api", api: "https://relay-mcp.example.com/v1" });
  const key = String(json.key);
  const API_ONLY = [403, "An API key works only on the web API, at your AI connector's address under /v1/."];
  for (const path of [ROUTES[1], CHATS, SAVES]) expect(await gate({ bearer: key }, "POST", path), path).toEqual(API_ONLY);
  for (const path of ["/apps/relay/api/timeline", CONNECTIONS, NOTES]) expect(await gate({ bearer: key }, "GET", path), path).toEqual(API_ONLY);
  expect(await call({ bearer: key }, "GET", "key")).toEqual({ status: 200, json: { device: "Backup script" } });
  expect(await apiKeyCaller({ DB: db.DB }, key)).toMatchObject({ kind: "key", personId: ANA, device: { id: json.id, reaches: "api" } });
  // A phone or chat key is refused by the web API's door, and a turned-off API key too.
  for (const sent of [phone, laptop]) {
    const refused = await apiKeyCaller({ DB: db.DB }, (sent as { bearer: string }).bearer) as Response;
    expect([refused.status, (await body(refused)).error.message])
      .toEqual([403, "A phone or chat key only sends. Make an API key on your Relay Everything page."]);
  }
  await call(matthew, "POST", "devices/off", { id: json.id });
  expect(await body(await apiKeyCaller({ DB: db.DB }, key) as Response)).toMatchObject({ error: { message: "This device key is turned off." } });
  // A server with no AI connector makes the key, and names no address.
  expect((await call(matthew, "POST", "devices", { name: "Other script", reaches: "api" })).json.api).toBeNull();
  expect((await call(matthew, "POST", "devices", { name: "Phone two", reaches: "phone" })).json.api).toBeNull();
});

it("hides a connected app's device row, which the AI apps card shows", async () => {
  db.sql.prepare(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-app', 'Claude', 'app:d-app', '', 0, 'app')`).run();
  expect((await call(matthew, "GET", "devices")).json.devices.map(device => device.id)).not.toContain("d-app");
});

it("turns a device's key off at once, keeps the first time it was turned off, and refuses an unknown id", async () => {
  const { json } = await call(matthew, "POST", "devices", { name: "Spare phone", reaches: "phone" });
  const key: Who = { bearer: String(json.key) };
  expect(await call(matthew, "POST", "devices/off", { id: json.id })).toEqual({ status: 200, json: { id: json.id, revokedAt: expect.any(Number) } });
  expect(await gate(key, "POST", ROUTES[1])).toEqual([403, "This device key is turned off."]);
  expect((await call(key, "GET", "key")).status).toBe(403);
  const first = rows("relay_devices").find(row => row.id === String(json.id))!.revoked_at;
  expect((await call(matthew, "POST", "devices/off", { id: json.id })).json.revokedAt).toBe(first);
  expect((await call(matthew, "POST", "devices/off", { id: "no-such-device" })).status).toBe(404);
  expect(await gate(phone, "POST", ROUTES[1])).toBeNull();
});

it("lets Ben turn off only his own devices, never Ana's", async () => {
  expect(await call(ben, "POST", "devices/off", { id: "d-phone" })).toEqual({ status: 404,
    json: { error: { code: "not_found", message: "You have no device with this id.", requestId: expect.any(String) } } });
  expect(rows("relay_devices").find(row => row.id === "d-phone")!.revoked_at).toBeNull();
  expect(directoryDb.sql.prepare("SELECT revoked_at FROM relay_keys WHERE device_id = 'd-phone'").get()).toEqual({ revoked_at: null });
  expect(await gate(phone, "POST", ROUTES[1])).toBeNull();
});

it("lets no device key and no one signed out list, add or turn off devices", async () => {
  // The actions' own check words every refusal the same way, so only the status shows here.
  for (const [who, status] of [[phone, 403], [laptop, 403], [lost, 403], [null, 401]] as const) {
    for (const [method, route, input] of [["GET", "devices", undefined], ["POST", "devices", { name: "Mine", reaches: "phone" }],
      ["POST", "devices/off", { id: "d-phone" }]] as const) {
      expect((await call(who, method, route, input)).status, `${method} ${route}`).toBe(status);
    }
  }
  expect(rows("relay_devices")).toHaveLength(4);
  expect(directoryDb.sql.prepare("SELECT count(*) AS count FROM relay_keys WHERE revoked_at IS NULL").get()).toEqual({ count: 4 });
});
