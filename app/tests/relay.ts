// What Relay Everything's API tests share: two people, Ana and Ben, each with a space run by the real Space class over
// node:sqlite; Ana's devices and keys; a stand-in bucket and queue; and a call through the app router.
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import { beforeEach, vi } from "vitest";
import type { AccessIdentity } from "../worker/access";
import { handleApp } from "../worker/apps/index";
import { hashToken } from "../worker/apps/relay/people";
import { Space } from "../worker/spaces-worker";
import { body } from "./body";
import { fakeEnv } from "./env";
import { database } from "./employee-access/connections";

export const NOW = Date.UTC(2026, 10, 5, 14, 0);
export const ANA = "aaaaaaaa-0000-4000-8000-00000000000a";
export const BEN = "bbbbbbbb-0000-4000-8000-00000000000b";

/** A device key: `rek_` and 43 base64url letters, as the page makes them. */
export const makeKey = (name: string) => `rek_${name.padEnd(43, "x")}`;
export const KEYS = { phone: makeKey("phone"), ipad: makeKey("ipad"), lost: makeKey("lost"), laptop: makeKey("laptop"), ben: makeKey("ben") };
export const SESSIONS = { ana: "ana-session-token", ben: "ben-session-token" };

/** Who calls: a device key, a signed-in browser, or an identity Access checked. */
export type Who = { bearer: string } | { cookie: string } | AccessIdentity | null;
const claims = { iss: "https://relay.cloudflareaccess.com", aud: "relay-app", exp: 9999999999 };
export const deviceKey = (clientId: string): AccessIdentity => ({ kind: "service", id: clientId, claims: { ...claims, common_name: clientId } });
export const phone: Who = { bearer: KEYS.phone };
export const ipad: Who = { bearer: KEYS.ipad };
export const lost: Who = { bearer: KEYS.lost };
/** A Claude Code computer's key: it only sends chats. */
export const laptop: Who = { bearer: KEYS.laptop };
export const benPhone: Who = { bearer: KEYS.ben };
export const checker = deviceKey("checker.access");
/** Ana, signed in on the page. */
export const matthew: Who = { cookie: SESSIONS.ana };
export const ben: Who = { cookie: SESSIONS.ben };
export const owner: AccessIdentity = { kind: "user", id: "ana@example.com", claims: { ...claims, email: "ana@example.com", sub: "a" } };

/** The bucket's objects by key, and its calls; `failing` makes the next put throw; a list page holds two keys. */
export const bucket = { objects: new Map<string, Uint8Array>(), failing: false,
  put: vi.fn(async (key: string, data: ArrayBuffer | Uint8Array) => {
    if (bucket.failing) throw new Error("R2 is down");
    bucket.objects.set(key, new Uint8Array(data));
  }),
  get: vi.fn(async (key: string) => {
    const data = bucket.objects.get(key);
    return data ? { size: data.byteLength, arrayBuffer: async () => data.slice().buffer } : null;
  }),
  // As R2's, the cursor goes on after the last key given, so a page deleted meanwhile skips no later key.
  list: vi.fn(async ({ prefix, cursor = "" }: { prefix: string; cursor?: string }) => {
    const keys = [...bucket.objects.keys()].filter(key => key.startsWith(prefix) && key > cursor).sort();
    return { objects: keys.slice(0, 2).map(key => ({ key })), truncated: keys.length > 2, cursor: keys[1] };
  }),
  delete: vi.fn(async (keys: string[]) => { for (const key of keys) bucket.objects.delete(key); }) };

/** The webhooks' queue: each message's body, in order; `failing` makes the next send throw. */
export const queue = { sent: [] as unknown[], failing: false,
  sendBatch: vi.fn(async (messages: { body: unknown }[]) => {
    if (queue.failing) throw new Error("The queue is down");
    queue.sent.push(...messages.map(message => message.body));
  }) };

const toSql = (value: unknown) => (value instanceof ArrayBuffer ? new Uint8Array(value) : value) as SQLInputValue;
const fromSql = (row: object) => Object.fromEntries(Object.entries(row).map(([name, value]) =>
  [name, value instanceof Uint8Array ? value.slice().buffer : value]));

/** A Durable Object's storage over node:sqlite, as much of it as the Space class uses. */
function fakeStorage() {
  let sql = new DatabaseSync(":memory:");
  sql.exec("PRAGMA foreign_keys = ON");
  const state = { alarm: null as number | null, get sql() { return sql; } };
  const storage = {
    sql: { exec(query: string, ...params: unknown[]) {
      // A migration holds several statements, as the runtime's exec takes them; node:sqlite takes those only by exec.
      if (!params.length && /\b(?:CREATE|DROP)\b/.test(query)) { sql.exec(query); return { toArray: () => [], rowsWritten: 0 }; }
      // As on the runtime, rowsWritten counts a trigger's writes too.
      const total = () => Number((sql.prepare("SELECT total_changes() AS count").get() as { count: number }).count);
      const before = total();
      const rows = sql.prepare(query).all(...params.map(toSql)).map(fromSql);
      const rowsWritten = total() - before;
      return { toArray: () => rows, rowsWritten };
    } },
    transactionSync<T>(run: () => T): T {
      sql.exec("SAVEPOINT space");
      try { const result = run(); sql.exec("RELEASE space"); return result; }
      catch (error) { sql.exec("ROLLBACK TO space"); sql.exec("RELEASE space"); throw error; }
    },
    getAlarm: async () => state.alarm,
    setAlarm: async (at: number) => { state.alarm = at; },
    deleteAlarm: async () => { state.alarm = null; },
    deleteAll: async () => { sql = new DatabaseSync(":memory:"); },
  };
  return { storage, state };
}

/** A SPACES namespace: each name gets the real Space class over its own database. A stub's calls go through
 *  structuredClone, as RPC copies values. `sql(name)` reads a space's database for a test. */
export function fakeSpaces(more: object = {}) {
  const objects = new Map<string, { space: Space; state: ReturnType<typeof fakeStorage>["state"]; ready: Promise<unknown> }>();
  const open = (name: string) => {
    let found = objects.get(name);
    if (!found) {
      const { storage, state } = fakeStorage();
      let ready: Promise<unknown> = Promise.resolve();
      const ctx = { storage, blockConcurrencyWhile: (run: () => Promise<unknown>) => (ready = run()) };
      const space = new Space(ctx as unknown as DurableObjectState, { RELAY_WEBHOOKS: queue, ...more } as never);
      found = { space, state, ready };
      objects.set(name, found);
    }
    return found;
  };
  const stub = (name: string) => new Proxy({}, { get: (_, method: string) => async (...args: unknown[]) => {
    const { space, ready } = open(name);
    await ready;
    const result = await (space as unknown as Record<string, (...values: unknown[]) => unknown>)[method](...structuredClone(args));
    if (method === "deleteEverything") objects.delete(name);
    return structuredClone(result);
  } });
  const SPACES = { idFromName: (name: string) => ({ name }), get: (id: { name: string }) => stub(id.name) } as unknown as DurableObjectNamespace;
  return { SPACES, objects, open, sql: (name: string) => open(name).state.sql, alarmOf: (name: string) => open(name).state.alarm,
    alarm: (name: string) => open(name).space.alarm() };
}

export let directoryDb: ReturnType<typeof database>;
export let spaces: ReturnType<typeof fakeSpaces>;
/** Ana's space's database as `sql`, and the directory as `DB`: the two a route test reads and seeds. */
export let db: { sql: DatabaseSync; DB: D1Database };

const key = async (key: string, person: string, device: string, reaches: string, revoked: number | null = null) =>
  directoryDb.sql.prepare("INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at, revoked_at) VALUES (?, ?, ?, ?, ?, ?)")
    .run(await hashToken(key), person, device, reaches, NOW, revoked);

beforeEach(async () => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
  directoryDb = database();
  spaces = fakeSpaces();
  db = { sql: spaces.sql(ANA), DB: directoryDb.DB };
  const person = directoryDb.sql.prepare("INSERT INTO relay_people (id, email, created_at) VALUES (?, ?, ?)");
  person.run(ANA, "ana@example.com", NOW);
  person.run(BEN, "ben@example.com", NOW);
  const session = directoryDb.sql.prepare("INSERT INTO relay_sessions (token_sha256, person_id, created_at, expires_at) VALUES (?, ?, ?, ?)");
  session.run(await hashToken(SESSIONS.ana), ANA, NOW, NOW + 86_400_000);
  session.run(await hashToken(SESSIONS.ben), BEN, NOW, NOW + 86_400_000);
  const device = (sql: DatabaseSync) => sql.prepare(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at,
    reaches) VALUES (?, ?, ?, '', ?, ?, ?)`);
  device(db.sql).run("d-phone", "Android phone", "rek:d-phone", NOW, null, "phone");
  device(db.sql).run("d-ipad", "iPad", "rek:d-ipad", NOW, null, "phone");
  device(db.sql).run("d-lost", "Old phone", "rek:d-lost", NOW, NOW, "phone");
  device(db.sql).run("d-laptop", "Laptop", "rek:d-laptop", NOW, null, "chats");
  device(spaces.sql(BEN)).run("d-ben", "Ben's phone", "rek:d-ben", NOW, null, "phone");
  await key(KEYS.phone, ANA, "d-phone", "phone");
  await key(KEYS.ipad, ANA, "d-ipad", "phone");
  await key(KEYS.lost, ANA, "d-lost", "phone", NOW);
  await key(KEYS.laptop, ANA, "d-laptop", "chats");
  await key(KEYS.ben, BEN, "d-ben", "phone");
  bucket.objects.clear();
  bucket.failing = false;
  bucket.put.mockClear();
  queue.sent = [];
  queue.failing = false;
});

export const env = (more: object = {}) =>
  fakeEnv({ DB: directoryDb.DB, SPACES: spaces.SPACES, RELAY_BUCKET: bucket, RELAY_WEBHOOKS: queue, ...more });

/** The request a caller makes: its key or cookie in the headers. */
export function request(who: Who, method: string, url: string, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  if (who && "bearer" in who) headers.set("Authorization", `Bearer ${who.bearer}`);
  if (who && "cookie" in who) headers.set("Cookie", `__Host-relay_session=${who.cookie}`);
  if (method === "POST" && !headers.has("Origin")) headers.set("Origin", new URL(url).origin);
  return new Request(url, { ...init, method, headers });
}
const identityOf = (who: Who) => who && "kind" in who ? who : null;

/** A Relay Everything route called as `who`: JSON for a POST, query fields otherwise; `more` adds bindings. */
export async function call(who: Who, method: string, route: string, input?: Record<string, unknown>, more?: object) {
  const query = method !== "POST" && input ? `?${new URLSearchParams(input as Record<string, string>)}` : "";
  const response = await handleApp(request(who, method, `https://relay.example.com/apps/relay/api/${route}${query}`,
    method === "POST" ? { headers: { "content-type": "application/json" }, body: JSON.stringify(input) } : {}), env(more), identityOf(who));
  return { status: response.status, json: await body(response) };
}

/** A table's rows in a person's space, Ana's when no one is named. */
export const rows = (table: string, person = ANA) => spaces.sql(person).prepare(`SELECT * FROM ${table} ORDER BY rowid`).all();
