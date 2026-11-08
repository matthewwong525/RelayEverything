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

it("answers a phone key with its person's email and AI app and webhook names, and nothing else", async () => {
  addHook("w-1", "Home server", NOW - 2);
  addHook("w-2", "Notion sync", NOW - 1);
  const grants = connector();
  const answer = await call(phone, "GET", "connections", undefined, { RELAY_MCP: grants });
  expect(answer).toEqual({ status: 200, json: { email: "ana@example.com", aiApps: [{ name: "Claude" }],
    webhooks: [{ name: "Home server" }, { name: "Notion sync" }] } });
  expect(grants.list).toHaveBeenCalledWith(ANA);
  // No address, secret, kinds or send state leave.
  expect(JSON.stringify(answer.json)).not.toMatch(/db\.example|whsec|health|grant-claude|relay-mcp/);
  // The page's own sign-in reads the same.
  expect((await call(matthew, "GET", "connections", undefined, { RELAY_MCP: grants })).json).toEqual(answer.json);
});

it("gives Ben's phone and Ben only Ben's email and names", async () => {
  addHook("w-1", "Home server", NOW);
  for (const who of [benPhone, ben]) {
    const answer = await call(who, "GET", "connections", undefined, { RELAY_MCP: connector() });
    expect(answer).toEqual({ status: 200, json: { email: "ben@example.com", aiApps: [], webhooks: [] } });
    expect(JSON.stringify(answer.json)).not.toContain("ana@");
  }
});

it("lists webhooks with an empty AI apps list where the connector is not set up", async () => {
  addHook("w-1", "Home server", NOW);
  expect(await call(phone, "GET", "connections")).toEqual({ status: 200,
    json: { email: "ana@example.com", aiApps: [], webhooks: [{ name: "Home server" }] } });
});

it("answers an empty email to the preview checker, which has none", async () => {
  const checked = { RELAY_MCP: connector(), RELAY_CHECKER_SHA256: await hashToken("checker.access") };
  expect((await call(checker, "GET", "connections", undefined, checked)).json).toEqual({ email: "", aiApps: [], webhooks: [] });
});

it("refuses a chat key and no one signed in, and a phone key still reads no notes", async () => {
  expect((await call(laptop, "GET", "connections")).status).toBe(403);
  expect((await call(null, "GET", "connections")).status).toBe(401);
  for (const route of ["timeline", "webhooks", "ai-apps"]) {
    const response = await handleApp(request(phone, "GET", `https://relay.example.com/apps/relay/api/${route}`), env(), null);
    expect(response.status, route).toBe(403);
  }
});
