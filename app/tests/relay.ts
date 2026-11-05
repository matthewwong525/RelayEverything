// What Relay's API tests share: a database from the real migrations with three devices, a stand-in bucket, the
// callers, and a call through the app router as the Worker makes it.
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

/** The webhooks' queue: each message's body, in order; `failing` makes the next send throw. */
export const queue = { sent: [] as unknown[], failing: false,
  sendBatch: vi.fn(async (messages: { body: unknown }[]) => {
    if (queue.failing) throw new Error("The queue is down");
    queue.sent.push(...messages.map(message => message.body));
  }) };

export let db: ReturnType<typeof database>;
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
  db = database();
  const device = db.sql.prepare("INSERT INTO relay_devices VALUES (?, ?, ?, ?, ?, ?)");
  device.run("d-phone", "Android phone", "phone.access", "t1", NOW, null);
  device.run("d-pebble", "Pebble app", "pebble.access", "t2", NOW, null);
  device.run("d-lost", "Old phone", "lost.access", "t3", NOW, NOW);
  bucket.objects.clear();
  bucket.failing = false;
  bucket.put.mockClear();
  queue.sent = [];
  queue.failing = false;
});

export const env = (more: object = {}) =>
  fakeEnv({ DB: db.DB, RELAY_BUCKET: bucket, RELAY_PEBBLE_SIGNING: SECRET, RELAY_WEBHOOKS: queue, ...more });

/** A Relay route called as `who`: JSON for a POST, query fields for a GET. */
export async function call(who: AccessIdentity | null, method: string, route: string, input?: Record<string, unknown>) {
  const query = method === "GET" && input ? `?${new URLSearchParams(input as Record<string, string>)}` : "";
  const response = await handleApp(new Request(`https://relay.example.com/apps/relay/api/${route}${query}`, {
    method, ...(method === "POST" && { headers: { "content-type": "application/json" }, body: JSON.stringify(input) }) }), env(), who);
  return { status: response.status, json: await body(response) };
}

export const rows = (table: string) => db.sql.prepare(`SELECT * FROM ${table} ORDER BY rowid`).all();
