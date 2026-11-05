import { expect, it, vi } from "vitest";
import type { AccessIdentity } from "./access";
import { env, matthew, phone } from "../tests/relay";

const who = vi.hoisted(() => ({ current: null as AccessIdentity | null }));
vi.mock("./access.ts", async (original) => ({ ...await original<object>(), getAccessIdentity: async () => who.current }));
const { default: worker } = await import("./relay-only");
// A test sends a plain Request, which has no Cloudflare edge properties.
const fetch = worker.fetch as (request: Request, env: object) => Promise<Response>;

const assets = { fetch: vi.fn(async () => new Response("the Relay page")) };
async function send(as: AccessIdentity | null, method: string, path: string, input?: object) {
  who.current = as;
  const request = new Request(`https://relay.example.com${path}`, { method,
    ...(input && { headers: { "content-type": "application/json" }, body: JSON.stringify(input) }) });
  const response = await fetch(request, env({ ASSETS: assets, WONG_OWNER_EMAIL: matthew.id }));
  const text = await response.text();
  return { status: response.status, location: response.headers.get("location"), json: text.startsWith("{") ? JSON.parse(text) : text };
}

it("serves Relay's routes to the owner and its devices, with a device key only sending", async () => {
  const note = { clientId: "note-0001", text: "Order more TL3312 switches", createdAt: Date.now() };
  expect((await send(phone, "POST", "/apps/relay/api/notes", note)).json).toMatchObject({ added: true });
  expect((await send(phone, "GET", "/apps/relay/api/key")).json).toEqual({ device: "Android phone" });
  expect((await send(phone, "GET", "/apps/relay/api/timeline")).status).toBe(403);
  const timeline = await send(matthew, "GET", "/apps/relay/api/timeline");
  expect(timeline.status).toBe(200);
  expect(JSON.stringify(timeline.json)).toContain("TL3312");
  expect((await send(null, "GET", "/apps/relay/api/timeline")).status).toBe(401);
});

it("has no WongStack route, sends / to the Relay page, and serves the page from its files", async () => {
  for (const path of ["/apps/inbox/api/items", "/api/health", "/apps/relay/api", "/apps/relay/api/nothing"]) expect((await send(matthew, "GET", path)).status).toBe(404);
  expect(await send(matthew, "GET", "/")).toMatchObject({ status: 302, location: "https://relay.example.com/apps/relay/" });
  expect((await send(matthew, "GET", "/apps/relay/")).status).toBe(200);
  expect(assets.fetch).toHaveBeenCalledOnce();
});

it("runs Relay's schedule, and hands every queue batch to the webhooks", async () => {
  const sweep = vi.spyOn(await import("./apps/relay/webhooks/sweep"), "sweep").mockResolvedValue(undefined as never);
  await worker.scheduled!({} as ScheduledController, env() as never);
  expect(sweep).toHaveBeenCalledOnce();
  const batch = { queue: "my-relay-webhooks", messages: [], ackAll: vi.fn() } as unknown as MessageBatch;
  await expect(worker.queue!(batch, env() as never)).resolves.toBeUndefined();
});
