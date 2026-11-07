import { expect, it, vi } from "vitest";
import type { AccessIdentity } from "./access";
import { ANA, env, matthew, owner, phone, request, type Who } from "../tests/relay";

const who = vi.hoisted(() => ({ current: null as AccessIdentity | null }));
vi.mock("./access.ts", async (original) => ({ ...await original<object>(), getAccessIdentity: async () => who.current }));
const { default: worker } = await import("./relay-only");
// A test sends a plain Request, which has no Cloudflare edge properties.
const fetch = worker.fetch as (request: Request, env: object) => Promise<Response>;

const assets = { fetch: vi.fn(async () => new Response("the Relay Everything page")) };
/** A call as `as`: Access's identity when it is one, else its key or cookie; `more` adds bindings. */
async function send(as: Who, method: string, path: string, input?: object, more: object = {}) {
  who.current = as && "kind" in as ? as : null;
  const sent = request(as, method, `https://relay.example.com${path}`,
    input ? { headers: { "content-type": "application/json" }, body: JSON.stringify(input) } : {});
  const response = await fetch(sent, env({ ASSETS: assets, WONG_OWNER_EMAIL: "ana@example.com", ...more }));
  const text = await response.text();
  return { status: response.status, location: response.headers.get("location"), json: text.startsWith("{") ? JSON.parse(text) : text };
}
const behindAccess = { RELAY_SIGN_IN: "access" };

it("serves Relay Everything's routes to the owner and its devices, with a device key only sending", async () => {
  const note = { clientId: "note-0001", text: "Order more TL3312 switches", createdAt: Date.now() };
  expect((await send(phone, "POST", "/apps/relay/api/notes", note)).json).toMatchObject({ added: true });
  expect((await send(phone, "GET", "/apps/relay/api/key")).json).toEqual({ device: "Android phone" });
  expect((await send(phone, "GET", "/apps/relay/api/timeline")).status).toBe(403);
  const timeline = await send(matthew, "GET", "/apps/relay/api/timeline");
  expect(timeline.status).toBe(200);
  expect(JSON.stringify(timeline.json)).toContain("TL3312");
  expect((await send(null, "GET", "/apps/relay/api/timeline")).status).toBe(401);
});

it("has no WongStack route, sends / to the Relay Everything page, and serves the page from its files", async () => {
  for (const path of ["/apps/inbox/api/items", "/api/health", "/apps/relay/api", "/apps/relay/api/nothing"]) expect((await send(matthew, "GET", path)).status).toBe(404);
  expect(await send(matthew, "GET", "/")).toMatchObject({ status: 302, location: "https://relay.example.com/apps/relay/" });
  expect((await send(matthew, "GET", "/apps/relay/")).status).toBe(200);
  expect(assets.fetch).toHaveBeenCalledOnce();
});

it("behind Access, refuses a call with no person and no key, and lets a key and the owner's email through", async () => {
  for (const path of ["/apps/relay/", "/apps/relay/sign-in/methods"]) {
    expect(await send(null, "GET", path, undefined, behindAccess)).toMatchObject({ status: 401, json: "Unauthorized" });
  }
  expect((await send(phone, "GET", "/apps/relay/api/key", undefined, behindAccess)).json).toEqual({ device: "Android phone" });
  expect((await send(owner, "GET", "/apps/relay/api/timeline", undefined, behindAccess)).status).toBe(200);
});

it("answers its own sign-in without Access", async () => {
  const methods = await send(null, "GET", "/apps/relay/sign-in/methods");
  expect(methods.status).toBe(200);
  expect(methods.json).toMatchObject({ apple: false, google: false });
  expect((await send(null, "GET", "/apps/relay/sign-in/nothing")).status).toBe(404);
});

it("hands every queue batch to the webhooks, which drop a message from before spaces and a webhook that is gone", async () => {
  const messages = [{ webhook: "w-old" }, { webhook: "w-gone", person: ANA }].map(body => ({ body, ack: vi.fn(), retry: vi.fn() }));
  const batch = { queue: "relay-everything-webhooks", messages, ackAll: vi.fn() } as unknown as MessageBatch;
  await worker.queue!(batch, env() as never);
  for (const message of messages) expect(message.ack).toHaveBeenCalledOnce();
});
