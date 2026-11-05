// What Relay's API tests share: a database from the real migrations with three devices and a chat key, a stand-in
// bucket, the callers, and a call through the app router as the Worker makes it.
import { beforeEach, vi } from "vitest";
import type { AccessIdentity } from "../worker/access";
import { handleApp } from "../worker/apps/index";
import { body } from "./body";
import { fakeEnv } from "./env";
import { database } from "./employee-access/connections";

export const NOW = Date.UTC(2026, 10, 5, 14, 0);
export const SECRET = "relay-test-signing-secret-0123456789";

const claims = { iss: "https://relay.cloudflareaccess.com", aud: "relay-app", exp: 9999999999 };
export const deviceKey = (clientId: string): AccessIdentity => ({ kind: "service", id: clientId, claims: { ...claims, common_name: clientId } });
export const phone = deviceKey("phone.access");
export const pebbleApp = deviceKey("pebble.access");
export const lost = deviceKey("lost.access");
/** A Claude Code computer's key: it only sends chats. */
export const laptop = deviceKey("laptop.access");
export const checker = deviceKey("checker.access");
export const matthew: AccessIdentity = { kind: "user", id: "matthew@example.com", claims: { ...claims, email: "matthew@example.com", sub: "m" } };

/** The bucket's objects by key, and its calls; `failing` makes the next put throw. */
export const bucket = { objects: new Map<string, Uint8Array>(), failing: false,
  put: vi.fn(async (key: string, data: ArrayBuffer) => {
    if (bucket.failing) throw new Error("R2 is down");
    bucket.objects.set(key, new Uint8Array(data));
  }),
  get: vi.fn(async (key: string, options?: { range?: { offset: number; length: number } }) => {
    const data = bucket.objects.get(key);
    const { offset = 0, length = data?.byteLength } = options?.range ?? {};
    return data ? { body: new Blob([data.slice(offset, offset + length!)]).stream(), size: data.byteLength } : null;
  }),
  head: vi.fn(async (key: string) => {
    const data = bucket.objects.get(key);
    return data ? { size: data.byteLength } : null;
  }) };

export let db: ReturnType<typeof database>;
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
  db = database();
  const device = db.sql.prepare("INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches) VALUES (?, ?, ?, ?, ?, ?, ?)");
  device.run("d-phone", "Android phone", "phone.access", "t1", NOW, null, "phone");
  device.run("d-pebble", "Pebble app", "pebble.access", "t2", NOW, null, "phone");
  device.run("d-lost", "Old phone", "lost.access", "t3", NOW, NOW, "phone");
  device.run("d-laptop", "Laptop", "laptop.access", "t4", NOW, null, "chats");
  bucket.objects.clear();
  bucket.failing = false;
  bucket.put.mockClear();
});

export const env = (more: object = {}) => fakeEnv({ DB: db.DB, RELAY_BUCKET: bucket, RELAY_PEBBLE_SIGNING: SECRET, ...more });

/** A Relay route called as `who`: JSON for a POST, query fields for a GET or DELETE; `more` adds bindings. */
export async function call(who: AccessIdentity | null, method: string, route: string, input?: Record<string, unknown>, more?: object) {
  const query = method !== "POST" && input ? `?${new URLSearchParams(input as Record<string, string>)}` : "";
  const response = await handleApp(new Request(`https://relay.example.com/apps/relay/api/${route}${query}`, {
    method, ...(method === "POST" && { headers: { "content-type": "application/json" }, body: JSON.stringify(input) }) }), env(more), who);
  return { status: response.status, json: await body(response) };
}

export const rows = (table: string) => db.sql.prepare(`SELECT * FROM ${table} ORDER BY rowid`).all();
