import { Webhook } from "standardwebhooks";
import { afterEach, expect, it, vi } from "vitest";
import { body } from "../../../tests/body";
import { fakeEnv } from "../../../tests/env";
import { ANA, BEN, ben, benPhone, bucket, call, checker, db, env, laptop, lost, matthew, NOW, owner, phone, queue, request, rows,
  type Who } from "../../../tests/relay";
import { handleApp } from "../index";
import { CHECKER_PERSON, relayGate } from "./caller";
import { consume } from "./webhooks/send.ts";

// The page writes notes as the space's own Web device, as emailed notes come from Email: design of flutter-web-app.
const MINUTE = 60_000;
const ORIGIN = "https://relay.example.com";
const SECRET = "whsec_dGVzdC1vbmx5LXNlY3JldC1mb3ItdGhlLXNlbmRlcg==";
const PDF = { id: "file-web-0001", name: "plan.pdf", type: "application/pdf", size: 3 };
const identityOf = (who: Who) => who && "kind" in who ? who : null;
afterEach(() => { vi.unstubAllGlobals(); });

const write = (who: Who, more: Record<string, unknown> = {}) =>
  call(who, "POST", "notes", { clientId: "web-note-0001", text: "Ideas for the trip", createdAt: NOW - MINUTE, ...more });
/** A route called as `who` from `origin`: DELETE sends its input as a query, as the page does. */
async function from(origin: string | null, who: Who, method: string, route: string, input: Record<string, unknown> = {}) {
  const json = method !== "DELETE";
  const url = `${ORIGIN}/apps/relay/api/${route}${json ? "" : `?${new URLSearchParams(input as Record<string, string>)}`}`;
  const sent = request(who, method, url, { headers: { ...json && { "content-type": "application/json" }, ...origin && { Origin: origin } },
    ...json && { body: JSON.stringify(input) } });
  const headers = new Headers(sent.headers);
  if (!origin) headers.delete("Origin");
  const made = new Request(sent, { headers });
  const identity = identityOf(who);
  const refusal = await relayGate(made, fakeEnv({ DB: db.DB }), identity, new URL(url).pathname);
  const response = refusal ?? await handleApp(made, env(), identity);
  return { status: response.status, json: await body(response) };
}
const page = (who: Who, method: string, route: string, input?: Record<string, unknown>) => from(ORIGIN, who, method, route, input);
const webRows = (person = ANA) => rows("relay_devices", person).filter(row => row.token_client_id === "page:web");
const log = () => rows("relay_outbox").map(row => row.kind);

/** Sends every waiting webhook message, as the queue does, and answers each one's type and note's device name. */
async function delivered() {
  const sent: { body: string; headers: Record<string, string> }[] = [];
  vi.stubGlobal("fetch", vi.fn(async (_url: string, init: RequestInit) => {
    sent.push({ body: String(init.body), headers: init.headers as Record<string, string> });
    return new Response(null, { status: 204 });
  }));
  const messages = queue.sent.splice(0).map(message => ({ body: message, ack: vi.fn(), retry: vi.fn() }));
  await consume({ queue: "relay-everything-webhooks", messages } as unknown as MessageBatch, env());
  return sent.map(item => new Webhook(SECRET).verify(item.body, item.headers) as { type: string; data: { note: { device?: { name: string } } } })
    .map(event => [event.type, event.data.note.device?.name ?? null]);
}

it("adds, changes and deletes a session's note as the space's Web device, made once, and each change goes to webhooks", async () => {
  db.sql.exec(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, active, sent_seq, created_at)
    VALUES ('hook-1', 'Database', 'https://hook-1.example.com/relay', '${SECRET}', '["notes"]', 1, 0, ${NOW})`);
  const { status, json } = await write(matthew);
  expect([status, json]).toEqual([200, { id: expect.any(String), added: true }]);
  expect(webRows()).toEqual([expect.objectContaining({ name: "Web", token_id: "", revoked_at: null, reaches: "inbox" })]);
  expect(rows("relay_notes").map(row => [row.id, row.device_id, row.client_id])).toEqual([[json.id, webRows()[0].id, "web-note-0001"]]);
  expect(await delivered()).toEqual([["note.created", "Web"]]);
  // A resend is stored once, and the page's next write uses the same device.
  expect((await write(matthew)).json).toEqual({ id: json.id, added: false });
  expect((await page(matthew, "PATCH", "notes", { clientId: "web-note-0001", text: "Ideas for the trip: Porto" })).json)
    .toEqual({ id: json.id, updated: true });
  expect(await delivered()).toEqual([["note.updated", "Web"]]);
  // The phone's next sync names the page's note by Web, and owns none of it; the page owns it.
  const synced = (await call(phone, "GET", "notes")).json.notes;
  expect(synced.map(note => [note.device, note.mine, note.text])).toEqual([["Web", false, "Ideas for the trip: Porto"]]);
  expect((await call(matthew, "GET", "notes")).json.notes.map(note => note.mine)).toEqual([true]);
  expect(await page(matthew, "DELETE", "notes", { clientId: "web-note-0001" })).toEqual({ status: 200, json: { id: json.id, deleted: true } });
  expect(await delivered()).toEqual([["note.deleted", null]]);
  expect(rows("relay_notes")).toEqual([]);
  expect(log()).toEqual(["note.created", "note.updated", "note.deleted"]);
  expect(webRows()).toHaveLength(1);
});

it("changes and deletes a phone's note by id from the page, which never owns it", async () => {
  const { json: { id } } = await call(phone, "POST", "notes", { clientId: "phone-note-01", text: "Milk", createdAt: NOW - MINUTE });
  expect((await page(matthew, "PATCH", "notes", { id, text: "Milk and eggs" })).json).toEqual({ id, updated: true });
  // A file goes only on a note the page wrote, and the phone's own clientId names no note of the page's.
  expect(await page(matthew, "PATCH", "notes", { id, text: "Milk", attachments: [PDF] })).toMatchObject({ status: 400, json: { error: { code: "not_own" } } });
  expect((await page(matthew, "PATCH", "notes", { clientId: "phone-note-01", text: "Bread" })).status).toBe(404);
  expect((await call(matthew, "GET", "notes")).json.notes.map(note => note.mine)).toEqual([false]);
  expect((await page(matthew, "DELETE", "notes", { id })).json).toEqual({ id, deleted: true });
  expect(log()).toEqual(["note.created", "note.updated", "note.deleted"]);
});

it("adds a file to the page's own note, and not to a phone's", async () => {
  await write(matthew, { attachments: [PDF] });
  const upload = (noteClientId: string, id: string) => handleApp(request(matthew, "POST", `${ORIGIN}/apps/relay/api/attachments`,
    { body: new Uint8Array([1, 2, 3]), headers: { "Content-Type": "application/pdf", "X-Note-Client-Id": noteClientId, "X-Attachment-Id": id } }), env(), null);
  expect(await (await upload("web-note-0001", PDF.id)).json()).toEqual({ ok: true, added: true });
  expect(rows("relay_attachments").map(row => [row.id, row.file_key])).toEqual([[PDF.id, `people/${ANA}/attachments/${PDF.id}`]]);
  const opened = await handleApp(request(matthew, "GET", `${ORIGIN}/apps/relay/api/attachment?id=${PDF.id}`), env(), null);
  expect(new Uint8Array(await opened.arrayBuffer())).toEqual(new Uint8Array([1, 2, 3]));
  await call(phone, "POST", "notes", { clientId: "phone-note-02", text: "Receipt", createdAt: NOW, attachments: [{ ...PDF, id: "file-phone-0001" }] });
  expect((await upload("phone-note-02", "file-phone-0001")).status).toBe(404);
  expect(bucket.put).toHaveBeenCalledOnce();
});

it("takes a change by session or Access email only from the page's own origin", async () => {
  const refusal = { status: 403, json: { error: { message: "This change must come from the Relay Everything page." } } };
  for (const who of [matthew, owner]) {
    for (const origin of ["https://evil.example", null]) {
      expect(await from(origin, who, "POST", "notes", { clientId: "evil-note-01", text: "Spam", createdAt: NOW }), `${origin}`).toMatchObject(refusal);
    }
  }
  const { json: { id } } = await write(matthew);
  for (const [method, input] of [["PATCH", { id, text: "Changed" }], ["DELETE", { id }]] as const) {
    for (const who of [matthew, owner]) expect(await from("https://evil.example", who, method, "notes", input), method).toMatchObject(refusal);
  }
  expect(rows("relay_notes").map(row => [row.client_id, row.text])).toEqual([["web-note-0001", "Ideas for the trip"]]);
  // From the page itself, Access's email writes as the same Web device.
  expect((await page(owner, "POST", "notes", { clientId: "access-note-01", text: "From the company app", createdAt: NOW })).status).toBe(200);
  expect(new Set(rows("relay_notes").map(row => row.device_id))).toEqual(new Set([webRows()[0].id]));
});

it("lets a session reach only its own space", async () => {
  const { json: { id } } = await write(matthew);
  expect((await write(ben, { text: "Ben's plan" })).status).toBe(200);
  expect(rows("relay_notes", BEN).map(row => row.text)).toEqual(["Ben's plan"]);
  expect(webRows(BEN)).toHaveLength(1);
  expect(webRows(BEN)[0].id).not.toBe(webRows()[0].id);
  expect((await page(ben, "PATCH", "notes", { id, text: "Ben was here" })).status).toBe(404);
  expect((await page(ben, "DELETE", "notes", { id })).status).toBe(404);
  expect((await call(ben, "GET", "notes")).json.notes.map(note => note.text)).toEqual(["Ben's plan"]);
  expect(rows("relay_notes").map(row => row.text)).toEqual(["Ideas for the trip"]);
  expect((await page(benPhone, "DELETE", "notes", { id })).status).toBe(404);
});

it("refuses a chat key, an API key, a turned-off key, the checker and no one, and makes no Web device", async () => {
  const { json: made } = await call(matthew, "POST", "devices", { name: "Backup script", reaches: "api" });
  // The checker's service token may not write through the app's actions, so it adds no note, even in its own space.
  for (const who of [laptop, { bearer: String(made.key) }, lost, checker, null]) {
    const { status } = await write(who);
    expect(status === 401 || status === 403, `${JSON.stringify(who)}: ${status}`).toBe(true);
  }
  expect([rows("relay_notes"), webRows(), rows("relay_notes", CHECKER_PERSON), webRows(CHECKER_PERSON)]).toEqual([[], [], [], []]);
});

it("makes no Web device on a read, and keeps it off the list of devices and out of Turn off", async () => {
  expect((await call(matthew, "GET", "notes")).json.notes).toEqual([]);
  expect(webRows()).toEqual([]);
  await write(matthew);
  const [web] = webRows();
  const listed = (await call(matthew, "GET", "devices")).json.devices;
  expect(listed.map(device => device.id)).not.toContain(web.id);
  expect((await call(matthew, "POST", "devices/off", { id: web.id })).status).toBe(404);
  expect(webRows()[0].revoked_at).toBeNull();
  expect((await write(matthew, { clientId: "web-note-0002" })).json).toMatchObject({ added: true });
});
