import { afterEach, expect, it, vi } from "vitest";
import { BEN, benPhone, call, db, env, matthew, NOW, phone, queue, rows } from "../../../tests/relay";
import { consume } from "./webhooks/send.ts";

const MIN = 60_000;
const cafe = (more: Record<string, unknown> = {}) => ({ kind: "stay", start: NOW, end: NOW + 10 * MIN, ongoing: true, lat: 43.651,
  lon: -79.383, name: "Corner Café", address: "Lake Drive", source: "map", ...more });
const walk = { kind: "trip", start: NOW - 20 * MIN, end: NOW, mode: "walking", km: 1.4 };
const send = (stays: object[], who = phone) => call(who, "POST", "stays", { stays });
const logged = () => rows("relay_outbox").filter(row => row.kind === "stay").map(row => row.ref);

it("stores each stay and trip once, wakes only a webhook ticked for places, and a resend wakes none", async () => {
  db.sql.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at)
    VALUES ('loc', 'Places database', 'https://db.example.com/relay', 'whsec_AAAA', '["notes","locations"]', 0, ?),
    ('notes', 'Notes only', 'https://notes.example.com/relay', 'whsec_BBBB', '["notes"]', 0, ?)`).run(NOW, NOW);
  expect(await send([walk, cafe()])).toEqual({ status: 200, json: { received: 2, changed: 2 } });
  expect(queue.sent).toEqual([{ webhook: "loc", person: expect.any(String) }]);
  queue.sent = [];
  expect(await send([walk, cafe()])).toEqual({ status: 200, json: { received: 2, changed: 0 } });
  expect(queue.sent).toEqual([]);
  expect(logged()).toHaveLength(2);
  expect(rows("relay_stays").map(({ kind, name, source, mode, km, ongoing }) => ({ kind, name, source, mode, km, ongoing }))).toEqual([
    { kind: "trip", name: null, source: null, mode: "walking", km: 1.4, ongoing: 0 },
    { kind: "stay", name: "Corner Café", source: "map", mode: null, km: null, ongoing: 1 }]);
});

afterEach(() => vi.unstubAllGlobals());

it("sends a stay changed after it was logged once, as it is now, in one location.stays message", async () => {
  const sent: { type: string; data: { stays: { kind: string; ongoing: boolean; name: string | null; mode: string | null }[] } }[] = [];
  vi.stubGlobal("fetch", vi.fn(async (_url: string, init: RequestInit) => {
    sent.push(JSON.parse(String(init.body)));
    return new Response(null, { status: 204 });
  }));
  db.sql.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at) VALUES ('loc', 'Places database',
    'https://db.example.com/relay', 'whsec_dGVzdC1vbmx5LXNlY3JldC1mb3ItdGhlLXNlbmRlcg==', '["notes","locations"]', 0, ?)`).run(NOW);
  await send([walk, cafe()]);
  await send([cafe({ end: NOW + 65 * MIN, ongoing: false })]);
  const message = { body: queue.sent[0], ack: vi.fn(), retry: vi.fn() };
  await consume({ queue: "relay-everything-webhooks", messages: [message] } as unknown as MessageBatch, env());
  expect(message.ack).toHaveBeenCalledOnce();
  expect(sent.map(item => [item.type, item.data.stays.map(({ kind, ongoing, name, mode }) => [kind, ongoing, name, mode])])).toEqual([
    ["location.stays", [["trip", false, null, "walking"], ["stay", false, "Corner Café", null]]]]);
});

it("changes a stay that ended, and logs the change once", async () => {
  await send([cafe()]);
  expect((await send([cafe({ end: NOW + 65 * MIN, ongoing: false })])).json).toEqual({ received: 1, changed: 1 });
  expect((await send([cafe({ end: NOW + 65 * MIN, ongoing: false })])).json).toEqual({ received: 1, changed: 0 });
  expect(rows("relay_stays").map(row => [row.end_at, row.ongoing])).toEqual([[NOW + 65 * MIN, 0]]);
  expect(logged()).toHaveLength(2);
});

it("refuses a bad stay or trip, and a person's session", async () => {
  for (const stays of [[], [cafe({ end: NOW - 1 })], [cafe({ start: NOW / 1000 })], [cafe({ source: "guess" })], [cafe({ name: "" })],
    [{ ...walk, lat: 43 }], [{ ...walk, mode: "teleport" }], [{ ...walk, km: -1 }], [{ ...cafe(), kind: "visit" }],
    [cafe({ lat: undefined })], Array(501).fill(walk)]) {
    expect((await send(stays)).status, JSON.stringify(stays).slice(0, 80)).toBe(400);
  }
  // A chat key is refused before the route, by the device gate: device.test.ts.
  expect((await send([cafe()], matthew)).status).toBe(403);
  expect(rows("relay_stays")).toEqual([]);
});

it("keeps Ben's stays in his space: his stay at Ana's start never touches hers", async () => {
  await send([cafe()]);
  expect((await send([cafe({ name: "Ben's café" })], benPhone)).json.changed).toBe(1);
  expect(rows("relay_stays").map(row => row.name)).toEqual(["Corner Café"]);
  expect(rows("relay_stays", BEN).map(row => row.name)).toEqual(["Ben's café"]);
});
