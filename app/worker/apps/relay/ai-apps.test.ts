import { expect, it, vi } from "vitest";
import { ANA, BEN, ben, call, checker, matthew, NOW, phone } from "../../../tests/relay";
import { CHECKER_PERSON } from "./caller";
import { hashToken } from "./people";

const listed = { address: "https://relay-mcp.example.com/mcp", apps: [{ id: "grant-claude", name: "Claude", connectedAt: NOW }] };
/** The connector's Grants: Ana holds one grant, and no one else holds any. */
const connector = () => ({
  list: vi.fn(async (person: string) => person === ANA ? listed : { ...listed, apps: [] }),
  revoke: vi.fn(async (id: string, person: string) => person === ANA && id === "grant-claude"),
});

it("shows a person their own connected AI apps, and ends one when asked", async () => {
  const grants = connector();
  expect(await call(matthew, "GET", "ai-apps", undefined, { RELAY_MCP: grants })).toEqual({ status: 200, json: listed });
  expect(grants.list).toHaveBeenCalledWith(ANA);
  expect(await call(matthew, "POST", "ai-apps-disconnect", { id: "grant-claude" }, { RELAY_MCP: grants }))
    .toEqual({ status: 200, json: { id: "grant-claude" } });
  expect(grants.revoke).toHaveBeenCalledWith("grant-claude", ANA);
  expect((await call(matthew, "POST", "ai-apps-disconnect", { id: "../grant" }, { RELAY_MCP: grants })).status).toBe(400);
});

it("lets Ben see and end only his own, never Ana's", async () => {
  const grants = connector();
  expect(await call(ben, "GET", "ai-apps", undefined, { RELAY_MCP: grants })).toEqual({ status: 200, json: { ...listed, apps: [] } });
  expect(await call(ben, "POST", "ai-apps-disconnect", { id: "grant-claude" }, { RELAY_MCP: grants })).toEqual({ status: 404,
    json: { error: { code: "not_found", message: "You have no connected AI app with this id.", requestId: expect.any(String) } } });
  expect(grants.list.mock.calls).toEqual([[BEN]]);
  expect(grants.revoke.mock.calls).toEqual([["grant-claude", BEN]]);
});

it("refuses a device key and no one signed in, and changes nothing", async () => {
  const grants = connector();
  for (const [who, status] of [[phone, 403], [null, 401]] as const) {
    expect((await call(who, "GET", "ai-apps", undefined, { RELAY_MCP: grants })).status).toBe(status);
    expect((await call(who, "POST", "ai-apps-disconnect", { id: "grant-claude" }, { RELAY_MCP: grants })).status).toBe(status);
  }
  expect(grants.list).not.toHaveBeenCalled();
  expect(grants.revoke).not.toHaveBeenCalled();
});

it("gives the preview checker only its own test person's list", async () => {
  const grants = connector();
  expect((await call(checker, "GET", "ai-apps", undefined, { RELAY_MCP: grants, RELAY_CHECKER_SHA256: await hashToken("checker.access") })).status)
    .toBe(200);
  expect(grants.list).toHaveBeenCalledWith(CHECKER_PERSON);
});

it("says the connector is not set up where it has no binding, such as a local run", async () => {
  const unavailable = { error: { code: "unavailable", message: "The AI connector is not set up here.", requestId: expect.any(String) } };
  expect(await call(matthew, "GET", "ai-apps")).toEqual({ status: 503, json: unavailable });
  expect(await call(matthew, "POST", "ai-apps-disconnect", { id: "grant-claude" })).toEqual({ status: 503, json: unavailable });
});

