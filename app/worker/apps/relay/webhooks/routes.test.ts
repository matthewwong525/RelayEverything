import { Webhook } from "standardwebhooks";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { handleApp } from "../../index";
import { call, db, env, matthew, NOW, phone, queue, rows } from "../../../../tests/relay";
import { scheduled } from "../api.ts";

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;
const fetch = vi.fn(async () => new Response(null, { status: 204 }));
beforeEach(() => {
  fetch.mockClear();
  vi.stubGlobal("fetch", fetch);
});
afterEach(() => vi.unstubAllGlobals());

const add = (more: Record<string, unknown> = {}) =>
  call(matthew, "POST", "webhooks", { name: "Example database", url: "https://db.example.com/relay", kinds: [], ...more });
const note = (clientId: string, createdAt: number) => call(phone, "POST", "notes", { clientId, text: "Order more switches", createdAt });
const sample = (start: number) => ({ type: "steps", start, end: start + MINUTE, value: 100, unit: "count", source: "Health Connect" });
const list = async () => (await call(matthew, "GET", "webhooks")).json.webhooks;
const sweepAs = async (environment: string) => {
  const response = await handleApp(new Request("https://relay.example.com/apps/relay/api/webhooks/sweep", { method: "POST" }),
    env({ WONG_ENVIRONMENT: environment }), matthew);
  return { status: response.status, json: await response.json() };
};

it("lets only a signed-in person reach the webhooks, never a device key", async () => {
  for (const [route, method] of [["webhooks", "GET"], ["webhooks", "POST"], ["webhooks/test", "POST"], ["webhooks/sweep", "POST"]]) {
    expect((await call(phone, method, route, method === "POST" ? { id: "x" } : undefined)).status, route).toBe(403);
    expect((await call(null, method, route)).status, route).toBe(401);
  }
});

it("adds a webhook from now on, with notes always, and shows its secret only in that answer", async () => {
  await note("note-0001", NOW - MINUTE);
  const added = await add({ kinds: ["locations"] });
  expect(added.status).toBe(200);
  expect(added.json.secret).toMatch(/^whsec_/);
  expect(added.json.webhook).toEqual({ id: expect.any(String), name: "Example database", url: "https://db.example.com/relay",
    kinds: ["notes", "locations"], state: "working", waiting: 0, lastStatus: null, lastError: null, lastSentAt: null, nextTryAt: null,
    failingSince: null, createdAt: NOW, attempts: [] });
  expect(rows("relay_webhooks")[0]).toMatchObject({ sent_seq: 1, secret: added.json.secret });
  await note("note-0002", NOW);
  expect(await list()).toEqual([{ ...added.json.webhook, waiting: 1 }]);
  expect(JSON.stringify(await list())).not.toContain(added.json.secret);
  expect((await add({ name: " " })).status).toBe(400);
});

it("refuses an address it must not send to, and says why", async () => {
  const cases = { "http://db.example.com/": "address_not_https", "https://10.0.0.8/": "address_private", "nowhere": "address_invalid",
    "https://a:b@db.example.com/": "address_has_login", "https://relay.example.com/apps/relay/api/notes": "address_own_site" };
  for (const [url, code] of Object.entries(cases)) {
    const refused = await add({ url });
    expect([refused.status, refused.json.error.code], url).toEqual([400, code]);
  }
  expect((await add({ url: "https://10.0.0.8/" })).json.error.message).toBe("The address can't be this computer or a private network.");
  const { json: { webhook } } = await add();
  expect((await call(matthew, "POST", "webhooks/update", { id: webhook.id, url: "https://localhost/" })).json.error.code)
    .toBe("address_private");
  expect(rows("relay_webhooks")).toHaveLength(1);
});

it("renames, pauses and resumes a webhook, and a new address clears its failure", async () => {
  const { json: { webhook } } = await add();
  const update = (more: Record<string, unknown>) => call(matthew, "POST", "webhooks/update", { id: webhook.id, ...more });
  queue.sent = [];
  expect((await update({ name: "Archive", active: false })).json.webhook).toMatchObject({ name: "Archive", state: "paused" });
  expect(queue.sent).toEqual([]);
  expect((await update({ active: true })).json.webhook.state).toBe("working");
  expect(queue.sent).toEqual([{ webhook: webhook.id }]);
  db.sql.prepare("UPDATE relay_webhooks SET failing_since = ?, tries = 10, pending_seq = 3").run(NOW);
  expect((await update({ name: "Still failing" })).json.webhook.state).toBe("failing");
  expect((await update({ url: "https://db2.example.com/relay", kinds: ["health"] })).json.webhook).toMatchObject({ state: "working",
    url: "https://db2.example.com/relay", kinds: ["notes", "health"] });
  expect(rows("relay_webhooks")[0]).toMatchObject({ tries: 0, pending_seq: null, failing_since: null, name: "Still failing" });
  expect(await call(matthew, "POST", "webhooks/update", { id: "nobody", name: "x" })).toMatchObject({ status: 404,
    json: { error: { code: "not_found", message: "No webhook has this id." } } });
});

it("replaces a secret, and removes a webhook with its tries", async () => {
  const { json: { webhook, secret } } = await add();
  const replaced = await call(matthew, "POST", "webhooks/secret", { id: webhook.id });
  expect(replaced.json.secret).toMatch(/^whsec_/);
  expect(replaced.json.secret).not.toBe(secret);
  expect(rows("relay_webhooks")[0].secret).toBe(replaced.json.secret);
  await call(matthew, "POST", "webhooks/test", { id: webhook.id });
  expect(rows("relay_webhook_attempts")).toHaveLength(1);
  expect(await call(matthew, "POST", "webhooks/remove", { id: webhook.id })).toEqual({ status: 200, json: { removed: true } });
  expect([rows("relay_webhooks"), rows("relay_webhook_attempts")]).toEqual([[], []]);
  for (const route of ["remove", "secret", "test", "retry", "resend"]) {
    expect((await call(matthew, "POST", `webhooks/${route}`, { id: webhook.id, ...(route === "resend" && { since: NOW }) })).status, route)
      .toBe(404);
  }
});

it("sends a signed test, says what the address answered, and keeps the try on the card", async () => {
  const { json: { webhook, secret } } = await add();
  fetch.mockImplementationOnce(async () => new Response("nope", { status: 401 }));
  expect((await call(matthew, "POST", "webhooks/test", { id: webhook.id })).json).toEqual({ status: 401, ms: 0, error: null });
  const [[url, init]] = fetch.mock.calls as unknown as [string, RequestInit & { headers: Record<string, string> }][];
  expect(url).toBe("https://db.example.com/relay");
  expect(init.headers["webhook-id"]).toBe(`msg_${webhook.id}_test_${NOW}`);
  expect(new Webhook(String(secret)).verify(String(init.body), init.headers)).toEqual({ version: 1, type: "webhook.test",
    timestamp: new Date(NOW).toISOString(), data: { webhook: { id: webhook.id, name: "Example database" } } });
  expect((await list())[0].attempts).toEqual([{ at: NOW, type: "webhook.test", status: 401, ms: 0, error: null, first: null, last: null }]);
  db.sql.prepare("UPDATE relay_webhooks SET url = 'https://192.168.0.2/'").run();
  expect((await call(matthew, "POST", "webhooks/test", { id: webhook.id })).json.error.code).toBe("address_private");
  expect(fetch).toHaveBeenCalledOnce();
});

it("shows the last 20 tries of each webhook, newest first", async () => {
  const [{ json: one }, { json: two }] = [await add(), await add({ name: "Second" })];
  const attempt = db.sql.prepare("INSERT INTO relay_webhook_attempts (webhook_id, at, type, status, ms) VALUES (?, ?, 'note.created', 200, 5)");
  for (let index = 0; index < 22; index++) attempt.run(String(one.webhook.id), NOW - index * MINUTE);
  attempt.run(String(two.webhook.id), NOW);
  const views = await list();
  const [first, second] = ["Example database", "Second"].map(name => views.find(view => String(view.name) === name)!);
  expect(first.attempts).toEqual(Array.from({ length: 20 }, (_, index) => expect.objectContaining({ at: NOW - index * MINUTE })));
  expect(second.attempts).toHaveLength(1);
});

it("sends past data from a date, only of the kinds it takes, then carries on", async () => {
  await note("note-0001", NOW - 3 * DAY);
  await call(phone, "POST", "health", { samples: [sample(NOW - 2 * DAY)] });
  await note("note-0002", NOW - DAY);
  const { json: { webhook } } = await add();
  queue.sent = [];
  const resend = (since: number) => call(matthew, "POST", "webhooks/resend", { id: webhook.id, since });
  expect((await resend(NOW - 2 * DAY - MINUTE)).json.webhook).toMatchObject({ state: "backfilling", waiting: 1 });
  expect(queue.sent).toEqual([{ webhook: webhook.id }]);
  expect(rows("relay_webhooks")[0]).toMatchObject({ sent_seq: 1, backfill_seq: 3 });
  expect((await resend(NOW - 4 * DAY)).json.webhook).toMatchObject({ state: "backfilling", waiting: 2 });
  expect((await resend(NOW)).json.webhook).toMatchObject({ state: "working", waiting: 0 });
  expect(rows("relay_webhooks")[0].sent_seq).toBe(3);
});

it("clears a failure when asked to try again", async () => {
  const { json: { webhook } } = await add();
  db.sql.prepare("UPDATE relay_webhooks SET failing_since = ?, tries = 10, lease_until = ?").run(NOW, NOW + MINUTE);
  queue.sent = [];
  expect((await call(matthew, "POST", "webhooks/retry", { id: webhook.id })).json.webhook.state).toBe("working");
  expect(rows("relay_webhooks")[0]).toMatchObject({ failing_since: null, tries: 0, lease_until: null });
  expect(queue.sent).toEqual([{ webhook: webhook.id }]);
});

it("runs the sweep by hand off production, and every 15 minutes there: it wakes each webhook behind and drops old tries", async () => {
  const { json: { webhook } } = await add();
  await add({ name: "Paused" });
  db.sql.prepare("UPDATE relay_webhooks SET active = 0 WHERE name = 'Paused'").run();
  const attempt = db.sql.prepare("INSERT INTO relay_webhook_attempts (webhook_id, at, type, status, ms) VALUES (?, ?, 'note.created', 200, 5)");
  attempt.run(String(webhook.id), NOW - 31 * DAY);
  attempt.run(String(webhook.id), NOW - 29 * DAY);
  queue.failing = true;
  const lost = vi.spyOn(console, "error").mockImplementation(() => undefined);
  await note("note-0001", NOW);
  expect(lost).toHaveBeenCalledWith("Relay webhooks: the wake-up was lost", expect.any(Error));
  queue.failing = false;
  expect(await sweepAs("production")).toMatchObject({ status: 403 });
  expect(queue.sent).toEqual([]);
  expect(await sweepAs("staging")).toEqual({ status: 200, json: { woken: 1 } });
  expect(queue.sent).toEqual([{ webhook: webhook.id }]);
  expect(rows("relay_webhook_attempts").map(row => row.at)).toEqual([NOW - 29 * DAY]);
  await scheduled(env());
  expect(queue.sent).toEqual([{ webhook: webhook.id }, { webhook: webhook.id }]);
  lost.mockRestore();
});
