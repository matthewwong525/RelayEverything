import { expect, it, vi } from "vitest";
import { ANA, ben, benPhone, call, checker, db, env, laptop, matthew, NOW, phone, request } from "../../../tests/relay";
import { hashToken } from "./people";
import { handleApp } from "../index";

/** The connector's Grants: Ana connected Claude, and no one else connected anything. */
const connector = () => ({ list: vi.fn(async (person: string) => ({ address: "https://relay-mcp.example.com/mcp",
  apps: person === ANA ? [{ id: "grant-claude", name: "Claude", connectedAt: NOW }] : [] })) });
const addHook = (id: string, name: string, at: number) => db.sql.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds,
  sent_seq, created_at, active) VALUES (?, ?, 'https://db.example.com/relay', 'whsec_secret', '["notes","health"]', 0, ?, ?)`)
  .run(id, name, at, id === "w-2" ? 0 : 1);
const MAIL = { RELAY_INBOX_MAIL_DOMAIN: "mail.example.com", RELAY_INBOX_HMAC_KEY: "inbox-test-key" };
/** Ana's phones and Claude Code laptop from the test helpers, all made at NOW; d-lost is signed out. */
const ANA_DEVICES = [
  { id: "d-ipad", name: "iPad", kind: "phone", since: NOW, lastChatAt: null },
  { id: "d-laptop", name: "Laptop", kind: "computer", since: NOW, lastChatAt: NOW - 5 },
  { id: "d-phone", name: "Android phone", kind: "phone", since: NOW, lastChatAt: null },
];
const chat = (id: string, lastAt: number) => db.sql.prepare(`INSERT INTO relay_chats (id, device_id, session_id, project, title, started_at,
  last_at, created_at) VALUES (?, 'd-laptop', ?, 'ring', 'Ring', 0, ?, 0)`).run(id, `s-${id}`, lastAt);

it("answers a phone key with its person's devices, AI apps, webhooks and addresses, and nothing else", async () => {
  addHook("w-1", "Home server", NOW - 2);
  addHook("w-2", "Notion sync", NOW - 1);
  chat("c-1", NOW - 50);
  chat("c-2", NOW - 5);
  // An API key and a connected app's row are no phone or computer.
  db.sql.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES
    ('d-api', 'Backup script', 'rek:d-api', '', 0, 'api'), ('d-app', 'Claude', 'app:d-app', '', 0, 'app')`);
  const grants = connector();
  const answer = await call(phone, "GET", "connections", undefined, { RELAY_MCP: grants, ...MAIL });
  expect(answer).toEqual({ status: 200, json: { email: "ana@example.com", thisDevice: "d-phone", devices: ANA_DEVICES,
    aiApps: [{ name: "Claude", connectedAt: NOW }], webhooks: [{ name: "Home server" }, { name: "Notion sync" }],
    notesAddress: expect.stringMatching(/^notes-[a-z2-7]{10}@mail\.example\.com$/), sharedAddress: "notes@mail.example.com" } });
  expect(grants.list).toHaveBeenCalledWith(ANA);
  // No key, address, secret, kinds, send state, app id or signed-out phone leaves.
  expect(JSON.stringify(answer.json)).not.toMatch(/rek_|db\.example|whsec|health|grant-claude|relay-mcp|d-lost|d-api|d-app/);
  // The page's own sign-in reads the same, with no device of its own, and the same private address.
  expect((await call(matthew, "GET", "connections", undefined, { RELAY_MCP: grants, ...MAIL })).json)
    .toEqual({ ...answer.json, thisDevice: null });
});

it("gives Ben's phone and Ben only Ben's email, devices and names", async () => {
  addHook("w-1", "Home server", NOW);
  for (const [who, thisDevice] of [[benPhone, "d-ben"], [ben, null]] as const) {
    const answer = await call(who, "GET", "connections", undefined, { RELAY_MCP: connector() });
    expect(answer).toEqual({ status: 200, json: { email: "ben@example.com", thisDevice, aiApps: [], webhooks: [],
      devices: [{ id: "d-ben", name: "Ben's phone", kind: "phone", since: NOW, lastChatAt: null }], notesAddress: null, sharedAddress: null } });
    expect(JSON.stringify(answer.json)).not.toMatch(/ana@|d-phone|d-laptop/);
  }
});

it("lists webhooks with an empty AI apps list where the connector is not set up, and no addresses where email is off", async () => {
  addHook("w-1", "Home server", NOW);
  expect(await call(phone, "GET", "connections")).toEqual({ status: 200, json: { email: "ana@example.com", thisDevice: "d-phone",
    devices: ANA_DEVICES.map(device => ({ ...device, lastChatAt: null })), aiApps: [], webhooks: [{ name: "Home server" }],
    notesAddress: null, sharedAddress: null } });
});

it("answers an empty email to the preview checker, which has none", async () => {
  const checked = { RELAY_MCP: connector(), RELAY_CHECKER_SHA256: await hashToken("checker.access") };
  expect((await call(checker, "GET", "connections", undefined, checked)).json).toEqual({ email: "", thisDevice: null, devices: [], aiApps: [],
    webhooks: [], notesAddress: null, sharedAddress: null });
});

it("refuses a chat key, an API key and no one signed in, and a phone key still reads no notes", async () => {
  const { json } = await call(matthew, "POST", "devices", { name: "Backup script", reaches: "api" });
  for (const who of [laptop, { bearer: String(json.key) }]) expect((await call(who, "GET", "connections")).status).toBe(403);
  expect((await call(null, "GET", "connections")).status).toBe(401);
  for (const route of ["timeline", "webhooks", "ai-apps"]) {
    const response = await handleApp(request(phone, "GET", `https://relay.example.com/apps/relay/api/${route}`), env(), null);
    expect(response.status, route).toBe(403);
  }
});
