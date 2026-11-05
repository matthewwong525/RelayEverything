import { expect, it, vi } from "vitest";
import { call, checker, matthew, NOW, phone } from "../../../tests/relay";

const listed = { address: "https://relay-mcp.example.com/mcp", apps: [{ id: "grant-claude", name: "Claude", connectedAt: NOW }] };
const connector = () => ({ list: vi.fn(async () => listed), revoke: vi.fn(async () => {}) });
const owned = (RELAY_MCP: object) => ({ RELAY_MCP, WONG_OWNER_EMAIL: "Matthew@example.com" });
const someone = { ...matthew, id: "someone@example.com", claims: { ...matthew.claims, email: "someone@example.com" } };

it("shows the owner the connected AI apps, and ends one when asked", async () => {
  const grants = connector();
  expect(await call(matthew, "GET", "ai-apps", undefined, owned(grants))).toEqual({ status: 200, json: listed });
  expect(await call(matthew, "POST", "ai-apps-disconnect", { id: "grant-claude" }, owned(grants)))
    .toEqual({ status: 200, json: { id: "grant-claude" } });
  expect(grants.revoke).toHaveBeenCalledWith("grant-claude");
  expect((await call(matthew, "POST", "ai-apps-disconnect", { id: "../grant" }, owned(grants))).status).toBe(400);
});

it("refuses anyone but the owner, a device key included, and changes nothing", async () => {
  const grants = connector();
  for (const who of [someone, phone, checker]) {
    expect((await call(who, "GET", "ai-apps", undefined, owned(grants))).status).toBe(403);
    expect((await call(who, "POST", "ai-apps-disconnect", { id: "grant-claude" }, owned(grants))).status).toBe(403);
  }
  // With no owner set, no one is the owner.
  expect((await call(matthew, "GET", "ai-apps", undefined, { RELAY_MCP: grants })).status).toBe(403);
  expect(grants.list).not.toHaveBeenCalled();
  expect(grants.revoke).not.toHaveBeenCalled();
});

it("lets the checker read the list on staging", async () => {
  const grants = connector();
  expect((await call(checker, "GET", "ai-apps", undefined, { ...owned(grants), WONG_ENVIRONMENT: "staging" })).status).toBe(200);
});

it("says the connector is not set up where it has no binding, such as a local run", async () => {
  expect(await call(matthew, "GET", "ai-apps", undefined, { WONG_OWNER_EMAIL: "matthew@example.com" })).toEqual({ status: 503,
    json: { error: { code: "unavailable", message: "The AI connector is not set up here.", requestId: expect.any(String) } } });
});
