import { Webhook } from "standardwebhooks";
import { afterEach, beforeEach, expect, it, vi, type Mock } from "vitest";
import { ANA, ben, BEN, benPhone, call, db, env, matthew, NOW, phone, queue, rows, spaces } from "../../../../tests/relay";
import { spaceOf, vouch, type SqlValue } from "../space.ts";
import { receive } from "../inbox/receive.ts";
import { consume, DELAYS, post, run } from "./send.ts";

const MINUTE = 60_000;
const SECRET = "whsec_dGVzdC1vbmx5LXNlY3JldC1mb3ItdGhlLXNlbmRlcg==";
type Sent = { url: string; headers: Record<string, string>; body: string; redirect: string };
const sent: Sent[] = [];
let answer: (index: number) => Promise<Response> | Response;

beforeEach(() => {
  sent.length = 0;
  answer = () => new Response(null, { status: 204 });
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    sent.push({ url, headers: init.headers as Record<string, string>, body: String(init.body), redirect: String(init.redirect) });
    return answer(sent.length - 1);
  }));
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

const hook = (id = "hook-1", more: Record<string, string | number | null> = {}) => {
  const row = { id, name: "Example database", url: "https://db.example.com/relay", secret: SECRET, kinds: '["notes"]', active: 1, sent_seq: 0,
    created_at: NOW, ...more };
  db.sql.prepare(`INSERT INTO relay_webhooks (${Object.keys(row)}) VALUES (${Object.keys(row).map(() => "?")})`).run(...Object.values(row));
};
const webhook = (id = "hook-1") => rows("relay_webhooks").find(row => row.id === id)!;
const note = (clientId: string, text = "Order more switches") => call(phone, "POST", "notes", { clientId, text, createdAt: NOW - MINUTE });
const anaSpace = () => spaceOf(env(), vouch("queue", ANA));
const ringNote = (id: string, more: { audio?: boolean; createdAt?: number } = {}) => db.sql.prepare(`INSERT INTO relay_notes (id, device_id, source,
  delivery_id, text, audio_key, recorded_at, created_at) VALUES (?, 'd-ipad', 'ring', ?, 'Ring note', ?, ?, ?)`)
  .run(id, `delivery-${id}`, more.audio ? anaSpace().files.nameOf(id) : null, NOW - 2 * MINUTE, more.createdAt ?? NOW);
/** Ana's space's SQL: `spy` sees each statement before it runs. */
const watchSql = (spy: (sql: string) => void) => {
  const { space } = spaces.open(ANA);
  const query = space.query.bind(space);
  return vi.spyOn(space, "query").mockImplementation((sql: string, params?: SqlValue[]) => {
    spy(sql);
    return query(sql, params);
  });
};
const wakeUp = (webhook: string, person = ANA) => ({ webhook, person });
const message = (body: unknown) => ({ body, ack: vi.fn(), retry: vi.fn() });
async function deliver(...bodies: unknown[]) {
  const messages = bodies.map(message);
  await consume({ queue: "relay-everything-webhooks", messages } as unknown as MessageBatch, env());
  return messages;
}
const bodies = () => sent.map(item => JSON.parse(item.body));
const types = () => bodies().map(item => item.type);
const at = (time: number) => vi.setSystemTime(time);

it("sends a stored note, signed, and moves the webhook's place only after a 2xx", async () => {
  hook();
  await note("note-0001");
  expect(queue.sent).toEqual([wakeUp("hook-1")]);
  const [delivered] = await deliver(wakeUp("hook-1"));
  expect(delivered.ack).toHaveBeenCalledOnce();
  expect(sent).toHaveLength(1);
  expect(sent[0]).toMatchObject({ url: "https://db.example.com/relay", redirect: "manual", headers: { "webhook-id": "msg_hook-1_1_1" } });
  expect(new Webhook(SECRET).verify(sent[0].body, sent[0].headers)).toMatchObject({ version: 1, type: "note.created",
    timestamp: new Date(NOW).toISOString(), data: { note: { text: "Order more switches", device: { name: "Android phone" }, audio: null } } });
  expect(webhook()).toMatchObject({ sent_seq: 1, pending_seq: null, lease_until: null, last_status: 204, last_sent_at: NOW, tries: 0 });
  expect(rows("relay_webhook_attempts")).toEqual([expect.objectContaining({ webhook_id: "hook-1", type: "note.created", first_seq: 1,
    last_seq: 1, status: 204, error: null })]);
  // Caught up, a second message sends nothing.
  await deliver(wakeUp("hook-1"));
  expect(sent).toHaveLength(1);
});

it("sends an emailed note as note.created from the Email device, with its file listed", async () => {
  hook();
  const file = { name: "receipt.pdf", type: "application/pdf", bytes: new TextEncoder().encode("%PDF") };
  await receive(env(), vouch("inbox", ANA), { channel: "email", id: "mail-0001", sentAt: NOW - MINUTE, text: "Receipt", files: [file] });
  expect(queue.sent).toEqual([wakeUp("hook-1")]);
  await deliver(wakeUp("hook-1"));
  expect(bodies()[0]).toMatchObject({ type: "note.created", data: { note: { text: "Receipt", source: "typed", device: { name: "Email" },
    recorded_at: new Date(NOW - MINUTE).toISOString(), attachments: [{ name: "receipt.pdf", content_type: "application/pdf", size: 4 }] } } });
});

it("tries a failed group again with the same id and body, and a parallel message waits for that retry", async () => {
  hook();
  await note("note-0001");
  answer = () => new Response("down", { status: 503 });
  const [first] = await deliver(wakeUp("hook-1"));
  expect(first.retry).toHaveBeenCalledWith({ delaySeconds: 30 });
  expect(webhook()).toMatchObject({ sent_seq: 0, pending_seq: 1, tries: 1, next_try_at: NOW + 30_000, last_status: 503,
    last_error: "Answered 503." });
  at(NOW + 1000);
  await note("note-0002");
  const [early] = await deliver(wakeUp("hook-1"));
  expect([early.ack.mock.calls.length, sent.length]).toEqual([1, 1]);
  at(NOW + 30_000);
  answer = () => new Response("ok");
  const [again] = await deliver(wakeUp("hook-1"));
  expect(again.ack).toHaveBeenCalledOnce();
  expect(sent[1].headers["webhook-id"]).toBe(sent[0].headers["webhook-id"]);
  expect(sent[1].body).toBe(sent[0].body);
  expect(bodies().map(item => item.data.note.text)).toEqual(["Order more switches", "Order more switches", "Order more switches"]);
  expect(sent.map(item => item.headers["webhook-id"])).toEqual(["msg_hook-1_1_1", "msg_hook-1_1_1", "msg_hook-1_2_2"]);
  expect(webhook()).toMatchObject({ sent_seq: 2, tries: 0, next_try_at: null, last_status: 200, last_error: null });
});

it("shows a webhook as failing after its last retry, then sends all that waits, in order, once tried again", async () => {
  const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
  hook();
  await note("note-0001", "First");
  answer = () => new Response(null, { status: 302, headers: { location: "https://elsewhere.example.com/" } });
  let time = NOW;
  for (const delay of [...DELAYS, null]) {
    const [delivered] = await deliver(wakeUp("hook-1"));
    if (delay === null) expect(delivered.ack).toHaveBeenCalledOnce();
    else expect(delivered.retry).toHaveBeenCalledWith({ delaySeconds: delay });
    time += (delay ?? 0) * 1000;
    at(time);
  }
  expect(sent).toHaveLength(10);
  expect(webhook()).toMatchObject({ failing_since: time, tries: 10, last_status: 302,
    last_error: "Answered with a redirect, which Relay Everything does not follow." });
  queue.sent = [];
  await note("note-0002", "Second");
  expect(queue.sent).toEqual([]);
  answer = () => new Response(null, { status: 204 });
  await deliver(wakeUp("hook-1"));
  expect(sent).toHaveLength(10);
  expect((await call(matthew, "POST", "webhooks/retry", { id: "hook-1" })).json.webhook).toMatchObject({ state: "working", waiting: 2 });
  await deliver(...queue.sent);
  expect(bodies().slice(10).map(item => item.data.note.text)).toEqual(["First", "Second"]);
  expect(webhook()).toMatchObject({ failing_since: null, sent_seq: 2 });
  expect(error).not.toHaveBeenCalled();
});

it("keeps its lease while the clock moves: sends every group in one run, and counts each failed try", async () => {
  hook();
  for (const id of ["note-0001", "note-0002", "note-0003"]) await note(id);
  // Each database call takes a millisecond, so each lease renewal writes a new time.
  watchSql(() => at(Date.now() + 1));
  await deliver(wakeUp("hook-1"));
  expect(sent).toHaveLength(3);
  expect(webhook()).toMatchObject({ sent_seq: 3, pending_seq: null, lease_until: null, tries: 0 });
  await note("note-0004");
  answer = () => new Response("down", { status: 503 });
  await deliver(wakeUp("hook-1"));
  expect(webhook()).toMatchObject({ sent_seq: 3, pending_seq: 4, lease_until: null, tries: 1 });
  // A wake before the retry is due stops at once and gives the lease back, so the retry is not turned away.
  await deliver(wakeUp("hook-1"));
  expect(webhook()).toMatchObject({ lease_until: null, tries: 1 });
  at(webhook().next_try_at as number);
  await deliver(wakeUp("hook-1"));
  expect(webhook()).toMatchObject({ sent_seq: 3, pending_seq: 4, lease_until: null, tries: 2 });
  expect(sent).toHaveLength(5);
});

it("says why a send failed: no answer in time, no connection, or a redirect", async () => {
  answer = () => {
    throw Object.assign(new Error("The operation timed out."), { name: "TimeoutError" });
  };
  expect(await post("https://db.example.com/", SECRET, "msg_x", "{}")).toEqual({ status: null, ms: 0, error: "No answer in 15 seconds." });
  answer = () => {
    throw new TypeError("fetch failed");
  };
  expect(await post("https://db.example.com/", SECRET, "msg_x", "{}")).toEqual({ status: null, ms: 0, error: "Could not connect." });
  answer = () => {
    throw "a string";
  };
  expect((await post("https://db.example.com/", SECRET, "msg_x", "{}")).error).toBe("Could not connect.");
});

it("stops sending to an address Relay Everything no longer allows, at once", async () => {
  hook("hook-1", { url: "https://127.0.0.1/relay" });
  await note("note-0001");
  const [delivered] = await deliver(wakeUp("hook-1"));
  expect(delivered.ack).toHaveBeenCalledOnce();
  expect(sent).toEqual([]);
  expect(webhook()).toMatchObject({ failing_since: NOW, last_error: "Relay Everything no longer sends to this address: address_private.", last_status: null });
});

it("runs one sender per webhook: a second waits for the lease, and a lease left by a stopped sender runs out", async () => {
  hook();
  await note("note-0001");
  expect(await Promise.all([run(env(), anaSpace(), "hook-1"), run(env(), anaSpace(), "hook-1")])).toEqual([null, null]);
  expect(sent).toHaveLength(1);
  await note("note-0002");
  db.sql.prepare("UPDATE relay_webhooks SET lease_until = ?").run(NOW + MINUTE);
  await run(env(), anaSpace(), "hook-1");
  expect(sent).toHaveLength(1);
  at(NOW + MINUTE + 1);
  await run(env(), anaSpace(), "hook-1");
  expect(sent).toHaveLength(2);
  expect(await run(env(), anaSpace(), "nobody")).toBeNull();
});

it("looks once more after giving up the lease, so a row stored meanwhile goes in the same run", async () => {
  hook();
  await note("note-0001");
  let stored = false;
  watchSql(sql => {
    if (!stored && sql.startsWith("UPDATE relay_webhooks SET lease_until = NULL")) {
      stored = true;
      ringNote("aaaaaaaa-0000-4000-8000-000000000001");
    }
  });
  await run(env(), anaSpace(), "hook-1");
  expect(types()).toEqual(["note.created", "note.created"]);
  expect(webhook().sent_seq).toBe(2);
});

it("sends nothing while paused, and stops when its owner changes it during a send", async () => {
  hook("hook-1", { active: 0 });
  await note("note-0001");
  await run(env(), anaSpace(), "hook-1");
  expect(sent).toEqual([]);
  db.sql.prepare("UPDATE relay_webhooks SET active = 1").run();
  answer = () => {
    db.sql.prepare("UPDATE relay_webhooks SET active = 0, lease_until = NULL").run();
    return new Response(null, { status: 204 });
  };
  await note("note-0002");
  expect(await run(env(), anaSpace(), "hook-1")).toBeNull();
  expect(sent).toHaveLength(1);
  // The address took it, but the change came first: it goes again on resume, and the receiver's upsert keeps one copy.
  expect(webhook()).toMatchObject({ sent_seq: 0, active: 0 });
});

it("waits for a ring note's recording, sends it when it comes, and skips a note deleted since", async () => {
  hook();
  ringNote("aaaaaaaa-0000-4000-8000-000000000001", { audio: true });
  const [early] = await deliver(wakeUp("hook-1"));
  expect(early.retry).toHaveBeenCalledWith({ delaySeconds: 30 });
  expect(sent).toEqual([]);
  await anaSpace().files.put("aaaaaaaa-0000-4000-8000-000000000001", new Uint8Array([0, 0, 0, 24]).buffer);
  ringNote("aaaaaaaa-0000-4000-8000-000000000002", { audio: true, createdAt: NOW - 3 * MINUTE });
  ringNote("aaaaaaaa-0000-4000-8000-000000000003");
  db.sql.prepare("DELETE FROM relay_notes WHERE id = 'aaaaaaaa-0000-4000-8000-000000000003'").run();
  await note("note-0001");
  await deliver(wakeUp("hook-1"));
  expect(bodies().map(item => [item.data.note.source, item.data.note.audio])).toEqual([
    ["ring", { content_type: "audio/mp4", base64: "AAAAGA==" }], ["ring", null], ["typed", null]]);
  expect(webhook()).toMatchObject({ sent_seq: 4, last_status: 204 });
});

it("sends health and location only to a webhook that takes them, in groups of one kind, in the order stored", async () => {
  hook("all", { kinds: '["notes","health","locations"]' });
  hook("notes");
  ringNote("aaaaaaaa-0000-4000-8000-000000000001");
  const sample = { type: "steps", start: NOW - 60 * MINUTE, end: NOW - 30 * MINUTE, value: 1200, unit: "count", source: "Health Connect" };
  await call(phone, "POST", "health", { samples: [sample, { ...sample, start: NOW - 30 * MINUTE, end: NOW - 10 * MINUTE }] });
  await call(phone, "POST", "locations", { points: [{ at: NOW - 2 * MINUTE, lat: 43.65, lon: -79.38, accuracy: 10 }] });
  await call(phone, "POST", "health", { samples: [{ ...sample, type: "heart_rate", unit: "bpm", value: 70 }] });
  // The point near the ring note gives it no place, so the notes-only webhook is not woken for it.
  expect(queue.sent).toEqual([wakeUp("all"), wakeUp("all"), wakeUp("all")]);
  await deliver(wakeUp("all"));
  expect(types()).toEqual(["note.created", "health.samples", "location.points", "health.samples"]);
  expect(bodies()[1].data.samples.map((item: { value: number }) => item.value)).toEqual([1200, 1200]);
  expect(bodies()[2].data.points[0]).toMatchObject({ lat: 43.65, device: { id: "d-phone", name: "Android phone" } });
  expect(sent.map(item => item.headers["webhook-id"])).toEqual(["msg_all_1_1", "msg_all_2_3", "msg_all_4_4", "msg_all_5_5"]);
  sent.length = 0;
  await deliver(wakeUp("notes"));
  expect(types()).toEqual(["note.created"]);
  expect(rows("relay_outbox").map(row => row.kind)).not.toContain("note.updated");
});

it("still sends a note.updated row already waiting from before the server stopped placing ring notes", async () => {
  hook();
  ringNote("aaaaaaaa-0000-4000-8000-000000000001");
  db.sql.prepare(`UPDATE relay_notes SET lat = 43.65, lon = -79.38, accuracy = 10, place_from = 'history'
    WHERE id = 'aaaaaaaa-0000-4000-8000-000000000001'`).run();
  db.sql.prepare("INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('note.updated', 'aaaaaaaa-0000-4000-8000-000000000001', ?, ?)")
    .run(NOW - 2 * MINUTE, NOW);
  await deliver(wakeUp("hook-1"));
  expect(types()).toEqual(["note.created", "note.updated"]);
  expect(bodies()[1].data.note).toMatchObject({ source: "ring", place: { lat: 43.65, from: "history" } });
  expect(webhook()).toMatchObject({ sent_seq: 2 });
});

it("sends changed and removed calendar events only to a webhook that takes the calendar", async () => {
  hook("cal", { kinds: '["notes","calendar"]' });
  hook("health", { kinds: '["notes","health"]' });
  const event = { key: "work:1:1", calendar: "Work", title: "Board meeting", start: NOW, end: NOW + 60 * MINUTE, allDay: false, people: [] };
  await call(phone, "POST", "calendar", { events: [event, { ...event, key: "work:2:2", title: "Sync" }], removed: [] });
  await call(phone, "POST", "calendar", { events: [{ ...event, title: "Board meeting, moved", start: NOW + 60 * MINUTE, end: NOW + 120 * MINUTE }],
    removed: ["work:2:2"] });
  expect(queue.sent).toEqual([wakeUp("cal"), wakeUp("cal")]);
  await deliver(wakeUp("cal"), wakeUp("health"));
  expect(types()).toEqual(["calendar.events"]);
  expect(bodies()[0].data.events.map((item: { title: string; status: string }) => [item.title, item.status]))
    .toEqual([["Board meeting, moved", "changed"], ["Sync", "removed"]]);
  expect(webhook("health").sent_seq).toBe(0);
});

it("sends a webhook made for notes only no health or calendar stored later, until its owner ticks them", async () => {
  const { json } = await call(matthew, "POST", "webhooks", { name: "Notes only", url: "https://db.example.com/relay", kinds: [] });
  const made = { id: String(json.webhook.id) };
  const sample = { type: "steps", start: NOW - 60 * MINUTE, end: NOW - 30 * MINUTE, value: 1200, unit: "count", source: "Health Connect" };
  await call(phone, "POST", "health", { samples: [sample] });
  const event = { key: "work:1:1", calendar: "Work", title: "Board meeting", start: NOW, end: NOW + 60 * MINUTE, allDay: false, people: [] };
  await call(phone, "POST", "calendar", { events: [event], removed: [] });
  await note("note-0001");
  await deliver(wakeUp(made.id));
  expect(types()).toEqual(["note.created"]);
  sent.length = 0;
  await call(matthew, "POST", "webhooks/update", { id: made.id, kinds: ["calendar"] });
  await call(phone, "POST", "calendar", { events: [{ ...event, title: "Board meeting, moved" }], removed: [] });
  await deliver(wakeUp(made.id));
  expect(types()).toEqual(["calendar.events"]);
});

it("sends 20 messages in a run, then queues the webhook again for the rest", async () => {
  hook();
  for (let index = 0; index < 21; index++) ringNote(`aaaaaaaa-0000-4000-8000-${String(index).padStart(12, "0")}`);
  const [delivered] = await deliver(wakeUp("hook-1"));
  expect([sent.length, delivered.ack.mock.calls.length, queue.sent]).toEqual([20, 1, [wakeUp("hook-1")]]);
  await deliver(...queue.sent);
  expect(sent).toHaveLength(21);
});

it("acks a message that names no webhook or no person, and tries a run that failed on our side again in 30 seconds", async () => {
  const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
  hook();
  await note("note-0001");
  const acked = await deliver(null, { webhook: 7, person: ANA }, { webhook: "hook-1" }, { webhook: "hook-1", person: 7 });
  expect(acked.map(({ ack }: { ack: Mock }) => ack.mock.calls.length)).toEqual([1, 1, 1, 1]);
  expect(sent).toEqual([]);
  watchSql(() => {
    throw new Error("The space is down");
  });
  const [failed] = await deliver(wakeUp("hook-1"));
  expect(failed.retry).toHaveBeenCalledWith({ delaySeconds: 30 });
  expect(error).toHaveBeenCalledWith("Relay Everything webhooks: a run failed", expect.any(Error));
});

it("sends Ben's note only to Ben's webhook, never to Ana's", async () => {
  hook("ana-hook");
  const added = await call(ben, "POST", "webhooks", { name: "Ben's database", url: "https://ben.example.com/relay", kinds: [] });
  const benHook = String(added.json.webhook.id);
  await call(benPhone, "POST", "notes", { clientId: "ben-0001", text: "Ben's errand", createdAt: NOW - MINUTE });
  expect(queue.sent).toEqual([wakeUp(benHook, BEN)]);
  // A message that names Ana with Ben's webhook opens Ana's space, where no such webhook is.
  await deliver(wakeUp("ana-hook"), wakeUp(benHook), ...queue.sent);
  expect(sent.map(item => [item.url, JSON.parse(item.body).data.note.text])).toEqual([["https://ben.example.com/relay", "Ben's errand"]]);
  expect([webhook("ana-hook").sent_seq, rows("relay_webhooks", BEN)[0].sent_seq]).toEqual([0, 1]);
  expect(rows("relay_notes")).toEqual([]);
});

it("names a note's files in its message at once, without waiting for their bytes", async () => {
  hook();
  await call(phone, "POST", "notes", { clientId: "note-files-01", text: "Receipt", createdAt: NOW - MINUTE,
    attachments: [{ id: "file-pdf-0001", name: "warranty.pdf", type: "application/pdf", size: 245_760 }] });
  await deliver(wakeUp("hook-1"));
  expect(bodies()[0].data.note.attachments).toEqual([{ id: "file-pdf-0001", name: "warranty.pdf", content_type: "application/pdf", size: 245_760 }]);
});
