import { expect, it, vi } from "vitest";
import type { AccessIdentity } from "./access";
import { ANA, directoryDb, env, matthew, NOW, owner, phone, request, rows, type Who } from "../tests/relay";
import { fixture, inboxEnv, mailTo } from "../tests/relay-inbox";
import { hold, KEEP_MS } from "./apps/relay/inbox/held";
import { addressOf } from "./apps/relay/inbox/links";

const who = vi.hoisted(() => ({ current: null as AccessIdentity | null }));
vi.mock("./access.ts", async (original) => ({ ...await original<object>(), getAccessIdentity: async () => who.current }));
const { default: worker } = await import("./relay-only");
// A test sends a plain Request, which has no Cloudflare edge properties.
const fetch = worker.fetch as (request: Request, env: object) => Promise<Response>;

const assets = { fetch: vi.fn(async (_request: Request) => new Response("the Relay Everything page")) };
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

it("has no WongStack route, opens the Relay Everything page at /, and serves the page from its files", async () => {
  for (const path of ["/apps/inbox/api/items", "/api/health", "/apps/relay/api", "/apps/relay/api/nothing"]) expect((await send(matthew, "GET", path)).status).toBe(404);
  assets.fetch.mockClear();
  for (const as of [matthew, null]) {
    expect(await send(as, "GET", "/")).toEqual({ status: 200, location: null, json: "the Relay Everything page" });
  }
  expect(await send(null, "GET", "/?next=%2Fapps%2Frelay%2Fsign-in%2Fconnect%3Fstate%3Dx")).toMatchObject({ status: 200, location: null });
  expect((await send(matthew, "GET", "/apps/relay/")).status).toBe(200);
  expect((await send(matthew, "GET", "/apps/relay/notes")).status).toBe(200);
  expect((await send(matthew, "GET", "/robots.txt")).status).toBe(200);
  expect(assets.fetch.mock.calls.map(([request]) => new URL(request.url).pathname))
    .toEqual(["/apps/relay/", "/apps/relay/", "/apps/relay/", "/apps/relay/", "/apps/relay/", "/robots.txt"]);
  expect(new URL(assets.fetch.mock.calls[2][0].url).search).toBe("?next=%2Fapps%2Frelay%2Fsign-in%2Fconnect%3Fstate%3Dx");
  expect((await send(phone, "GET", "/apps/relay/api/key")).json).toEqual({ device: "Android phone" });
});

it("behind Access, refuses a call with no person and no key, and lets a key and the owner's email through", async () => {
  for (const path of ["/apps/relay/", "/apps/relay/sign-in/methods"]) {
    expect(await send(null, "GET", path, undefined, behindAccess)).toMatchObject({ status: 401, json: "Unauthorized" });
  }
  expect((await send(phone, "GET", "/apps/relay/api/key", undefined, behindAccess)).json).toEqual({ device: "Android phone" });
  expect((await send(owner, "GET", "/apps/relay/api/timeline", undefined, behindAccess)).status).toBe(200);
  // A phone trades its sign-in code with no person and no key: its secret, checked by the route, protects it.
  const trade = await send(null, "POST", "/apps/relay/sign-in/phone/key", { code: "c", verifier: "v".repeat(43) }, behindAccess);
  expect([trade.status, trade.json.error.code]).toEqual([400, "invalid_input"]);
  expect((await send(null, "GET", "/apps/relay/sign-in/phone/key", undefined, behindAccess)).status).toBe(401);
  // A computer starts its sign-in and asks for its key the same way; the person's Connect page stays behind Access.
  for (const [path, input] of [["computer/start", { challenge: "short" }], ["computer/key", { verifier: "v".repeat(43) }]] as const) {
    const sent = await send(null, "POST", `/apps/relay/sign-in/${path}`, input, behindAccess);
    expect([sent.status, sent.json.error.code], path).toEqual([400, "invalid_input"]);
  }
  expect((await send(null, "GET", "/apps/relay/sign-in/computer?c=x", undefined, behindAccess)).status).toBe(401);
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

it("makes mail from Email Routing a note, and sweeps old kept mail each day", async () => {
  const address = (await addressOf(inboxEnv(), ANA))!;
  await worker.email!(mailTo(address, fixture("forwarded-pdf.eml")) as unknown as ForwardableEmailMessage, inboxEnv() as never);
  expect(rows("relay_notes").map(row => row.text)).toEqual([expect.stringMatching(/^Fwd: Your receipt/)]);
  await hold(inboxEnv(), "cy@example.com", { channel: "email", id: "m-1", sentAt: NOW, text: "Old", files: [] });
  vi.setSystemTime(NOW + KEEP_MS + 1);
  await worker.scheduled!({} as ScheduledController, inboxEnv() as never);
  expect(directoryDb.sql.prepare("SELECT count(*) AS count FROM relay_inbox_held").get()).toEqual({ count: 0 });
});

it("hands a new person's kept mail to the Worker to finish after the sign-in answers", async () => {
  const mail = { sent: [] as { text: string }[], send: vi.fn(async (message: { text: string }) => { mail.sent.push(message); return { messageId: "m" }; }) };
  const more = inboxEnv({ ASSETS: assets, RELAY_EMAIL: mail, RELAY_SIGN_IN_FROM: "sign-in@example.com", RELAY_SIGN_UP: "open",
    RELAY_SIGN_IN_LIMIT: { limit: async () => ({ success: true }) } });
  const post = (path: string, body: object) => new Request(`https://relay.example.com/apps/relay/sign-in/${path}`, { method: "POST",
    body: JSON.stringify(body), headers: { Origin: "https://relay.example.com", "content-type": "application/json" } });
  const ctx = { waitUntil: vi.fn((_work: Promise<unknown>) => undefined) };
  const signed = worker.fetch as (request: Request, env: object, ctx: object) => Promise<Response>;
  await signed(post("email", { email: "cy@example.com" }), more, ctx);
  expect((await signed(post("code", { email: "cy@example.com", code: /\d{6}/.exec(mail.sent[0].text)![0] }), more, ctx)).status).toBe(200);
  expect(ctx.waitUntil).toHaveBeenCalledOnce();
  await ctx.waitUntil.mock.calls[0][0];
});
