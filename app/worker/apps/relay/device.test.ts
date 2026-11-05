import { expect, it } from "vitest";
import { fakeEnv } from "../../../tests/env";
import { deviceGate, deviceOf } from "./device";
import { checker, db, deviceKey, laptop, lost, matthew, phone } from "../../../tests/relay";

// The fingerprint of checker.id, "checker.access".
const CHECKER_SHA256 = "6a6814c5281a7635cb9d9f881d7feae9b0d6159c868666fad3ffa0a164f4d999";
const ROUTES = ["pebble", "notes", "health", "locations"].map(route => `/apps/relay/api/${route}`);
const KEY = "/apps/relay/api/key";
const refusal = async (response: Response | null) =>
  [response?.status, ((await response?.json()) as { error: { message: string } } | undefined)?.error.message];
const gate = (who: Parameters<typeof deviceGate>[1], path: string, method = "GET") =>
  deviceGate({ DB: db.DB, RELAY_CHECKER_SHA256: CHECKER_SHA256 }, who, method, path);
const CHATS = "/apps/relay/api/chats";

it("lets a device key only send to Relay and check itself, and nothing else", async () => {
  for (const path of ROUTES) expect(await gate(phone, path, "POST"), path).toBeNull();
  expect(await gate(phone, KEY)).toBeNull();
  // A phone can't read notes, recordings, health or chats, even on an address it sends to.
  for (const [method, path] of [...ROUTES.map(route => ["GET", route]), ["POST", KEY], ["GET", "/apps/relay/api/timeline"],
    ["GET", "/apps/relay/api/audio"], ["GET", "/apps/relay/api/summary"], ["GET", "/apps/relay/api/ai-apps"], ["POST", "/apps/relay/api/ai-apps-disconnect"],
    ["GET", "/apps/relay/api/webhooks"], ["GET", "/apps/relay/"], ["GET", "/apps/hello/api/greeting"], ["GET", "/api/access/apps"], ["GET", "/api/health"],
    ["GET", "/"], ["POST", "/apps/relay/api/notes/x"], ["POST", CHATS], ["POST", "/apps/relay/api/chat-saves"], ["GET", CHATS],
    ["GET", "/apps/relay/api/chat"], ["DELETE", "/apps/relay/api/chat"], ["DELETE", ROUTES[1]]]) {
    expect(await refusal(await gate(phone, path, method)), `${method} ${path}`).toEqual([403, "A device key can only send to Relay."]);
  }
});

it("lets a chat key only send chats and saves, by POST, and nothing else", async () => {
  expect(await gate(laptop, CHATS, "POST")).toBeNull();
  expect(await gate(laptop, "/apps/relay/api/chat-saves", "POST")).toBeNull();
  expect(await gate(laptop, KEY)).toBeNull();
  for (const [method, path] of [["GET", CHATS], ["GET", "/apps/relay/api/chat"], ["DELETE", "/apps/relay/api/chat"], ["DELETE", CHATS],
    ["GET", "/apps/relay/api/chat-saves"], ...ROUTES.map(route => ["GET", route]), ...ROUTES.map(route => ["POST", route]),
    ["GET", "/apps/relay/api/summary"], ["GET", "/apps/relay/api/ai-apps"], ["GET", "/api/health"]]) {
    expect(await refusal(await gate(laptop, path, method)), `${method} ${path}`).toEqual([403, "A chat key can only send chats."]);
  }
  expect(await deviceOf({ DB: db.DB }, laptop)).toEqual({ id: "d-laptop", name: "Laptop", reaches: "chats" });
});

it("stops a revoked key everywhere, Relay included, and leaves the other devices working", async () => {
  for (const path of [...ROUTES, "/api/health"]) {
    expect(await refusal(await gate(lost, path)), path).toEqual([403, "This device key is turned off."]);
  }
  expect(await gate(phone, ROUTES[1], "POST")).toBeNull();
  expect(await deviceOf({ DB: db.DB }, lost)).toBeNull();
  expect(await deviceOf({ DB: db.DB }, phone)).toEqual({ id: "d-phone", name: "Android phone", reaches: "phone" });
});

it("leaves people and the checker to the usual checks, and refuses every other service token", async () => {
  for (const path of ["/api/access/apps", ROUTES[0]]) {
    expect(await gate(matthew, path)).toBeNull();
    expect(await gate(checker, path)).toBeNull();
    expect(await gate(null, path)).toBeNull();
    // A staging phone's key after a staging reset is on no list: it is no checker, and owns nothing.
    expect(await refusal(await gate(deviceKey("reset.access"), path)), path).toEqual([403, "This key is on no list of devices."]);
  }
  // With no checker named, the checker is one more unknown key.
  expect(await refusal(await deviceGate({ DB: db.DB }, checker, "GET", "/api/health"))).toEqual([403, "This key is on no list of devices."]);
  expect(await refusal(await deviceGate({}, phone, "GET", "/api/health"))).toEqual([403, "This key is on no list of devices."]);
  expect(await deviceOf({ DB: db.DB }, matthew)).toBeNull();
  expect(await deviceOf({ DB: db.DB }, checker)).toBeNull();
  const broken = fakeEnv({ DB: { withSession: () => { throw new Error("D1 is down"); } }, RELAY_CHECKER_SHA256: CHECKER_SHA256 });
  const refused = await deviceGate(broken, phone, "GET", "/api/health");
  expect([refused?.status, ((await refused?.json()) as { error: { code: string } } | undefined)?.error.code]).toEqual([503, "unavailable"]);
  expect(await deviceGate(broken, checker, "GET", "/api/health")).toBeNull();
});
