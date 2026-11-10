// The connector's /v1/ over Ana's made-up space, reached with a key of each kind: her computer (the sample rows'
// Laptop), her second computer, an API key, a phone, an old chat key, a turned-off key, and Ben's computer.
import { readFileSync } from "node:fs";
import { hashToken } from "../worker/apps/relay/people.ts";
import type { McpEnv } from "../worker/relay-mcp/env.ts";
import provider from "../worker/relay-mcp/index.ts";
import { database } from "./employee-access/connections.ts";
import { ANA, BEN, bucket, fakeSpaces, makeKey, queue } from "./relay.ts";

export const LAPTOP = "d0000000-0000-4000-8000-000000000004";
export const NOTE = (n: number) => `a0000000-0000-4000-8000-00000000000${n}`;
export const CHAT = (n: number) => `c0000000-0000-4000-8000-00000000000${n}`;
export const SPACE_ROWS = readFileSync(new URL("./relay-space-rows.sql", import.meta.url), "utf8");
export const V1_KEYS = { computer: makeKey("computer"), desktop: makeKey("desktop"), api: makeKey("api"), phone: makeKey("phone"), chats: makeKey("chats"),
  off: makeKey("off"), ben: makeKey("ben") };
const ctx = { waitUntil: () => {}, passThroughOnException: () => {}, props: {} } as unknown as ExecutionContext;

/** Each key's person, device, name and reach; the turned-off key was an API key. */
const DEVICES: [keyof typeof V1_KEYS, string, string, string, string][] = [
  ["computer", ANA, LAPTOP, "Laptop", "agent"], ["desktop", ANA, "d-desktop", "Desktop", "agent"], ["api", ANA, "d-api", "Backup script", "api"], ["phone", ANA, "d-phone", "Phone", "phone"],
  ["chats", ANA, "d-chats", "Old laptop", "chats"], ["off", ANA, "d-off", "Old script", "api"], ["ben", BEN, "d-ben", "Ben's laptop", "agent"]];

/** The connector with Ana's sample space and every key, and `more` bindings, such as KNOWLEDGE. */
export async function keyedConnector(more: object = {}) {
  const directory = database();
  const person = directory.sql.prepare("INSERT INTO relay_people (id, email, created_at) VALUES (?, ?, 0)");
  person.run(ANA, "ana@example.com");
  person.run(BEN, "ben@example.com");
  const spaces = fakeSpaces();
  spaces.sql(ANA).exec(SPACE_ROWS);
  for (const [name, owner, device, shown, reach] of DEVICES) {
    const off = name === "off" ? 1 : null;
    if (device !== LAPTOP) {
      spaces.sql(owner).prepare(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches)
        VALUES (?, ?, ?, '', 0, ?, ?)`).run(device, shown, `rek:${device}`, off, reach);
    }
    directory.sql.prepare("INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at, revoked_at) VALUES (?, ?, ?, ?, 0, ?)")
      .run(await hashToken(V1_KEYS[name]), owner, device, reach, off);
  }
  const env = { DB: directory.DB, SPACES: spaces.SPACES, RELAY_BUCKET: bucket, RELAY_WEBHOOKS: queue, RELAY_MCP_ADDRESS: "https://relay-mcp.example.com/",
    RELAY_SERVER_URL: "https://relay.example.com", ...more } as unknown as McpEnv;
  /** A /v1/ call with this key: a GET, a POST of `body` as JSON, or a POST with no body when `body` is null. */
  const v1 = async (path: string, key: string = V1_KEYS.computer, body?: unknown) => {
    const headers = { Authorization: `Bearer ${key}`, ...body !== undefined && body !== null && { "Content-Type": "application/json" } };
    const sent = body === null ? undefined : JSON.stringify(body);
    const response = await provider.fetch(new Request(`https://relay-mcp.example.com/v1/${path}`, body === undefined ? { headers }
      : { method: "POST", headers, body: sent }), env, ctx);
    return { status: response.status, json: await response.json() as Record<string, unknown> };
  };
  return { v1, spaces, env };
}
