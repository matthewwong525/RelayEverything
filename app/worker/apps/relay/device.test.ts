import { expect, it } from "vitest";
import { fakeEnv } from "../../../tests/env";
import { deviceGate, deviceOf } from "./device";
import { checker, db, deviceKey, lost, matthew, phone } from "../../../tests/relay";

// The fingerprint of checker.id, "checker.access".
const CHECKER_SHA256 = "6a6814c5281a7635cb9d9f881d7feae9b0d6159c868666fad3ffa0a164f4d999";
const ROUTES = ["pebble", "notes", "health", "locations", "timeline", "audio"].map(route => `/apps/relay/api/${route}`);
const refusal = async (response: Response | null) =>
  [response?.status, ((await response?.json()) as { error: { message: string } } | undefined)?.error.message];
const gate = (who: Parameters<typeof deviceGate>[1], path: string) => deviceGate({ DB: db.DB, RELAY_CHECKER_SHA256: CHECKER_SHA256 }, who, path);

it("lets a device key reach Relay's device routes, and nothing else", async () => {
  for (const path of ROUTES) expect(await gate(phone, path), path).toBeNull();
  for (const path of ["/apps/relay/api/summary", "/apps/relay/", "/apps/hello/api/greeting", "/api/access/apps", "/api/health", "/", "/apps/relay/api/notes/x"]) {
    expect(await refusal(await gate(phone, path)), path).toEqual([403, "A device key reaches only Relay."]);
  }
});

it("stops a revoked key everywhere, Relay included, and leaves the other devices working", async () => {
  for (const path of [...ROUTES, "/api/health"]) {
    expect(await refusal(await gate(lost, path)), path).toEqual([403, "This device key is turned off."]);
  }
  expect(await gate(phone, ROUTES[1])).toBeNull();
  expect(await deviceOf({ DB: db.DB }, lost)).toBeNull();
  expect(await deviceOf({ DB: db.DB }, phone)).toEqual({ id: "d-phone", name: "Android phone" });
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
  expect(await refusal(await deviceGate({ DB: db.DB }, checker, "/api/health"))).toEqual([403, "This key is on no list of devices."]);
  expect(await refusal(await deviceGate({}, phone, "/api/health"))).toEqual([403, "This key is on no list of devices."]);
  expect(await deviceOf({ DB: db.DB }, matthew)).toBeNull();
  expect(await deviceOf({ DB: db.DB }, checker)).toBeNull();
  const broken = fakeEnv({ DB: { withSession: () => { throw new Error("D1 is down"); } }, RELAY_CHECKER_SHA256: CHECKER_SHA256 });
  const refused = await deviceGate(broken, phone, "/api/health");
  expect([refused?.status, ((await refused?.json()) as { error: { code: string } } | undefined)?.error.code]).toEqual([503, "unavailable"]);
  expect(await deviceGate(broken, checker, "/api/health")).toBeNull();
});
