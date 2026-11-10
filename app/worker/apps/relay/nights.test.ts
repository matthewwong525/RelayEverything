import { afterEach, expect, it, vi } from "vitest";
import { BEN, benPhone, call, db, env, matthew, NOW, phone, queue, rows } from "../../../tests/relay";
import { consume } from "./webhooks/send.ts";

const MIN = 60_000;
const BED = NOW - 8 * 60 * MIN;
const steps = [{ stage: "core", start: BED + 15 * MIN, end: BED + 65 * MIN }, { stage: "deep", start: BED + 65 * MIN, end: BED + 120 * MIN },
  { stage: "rem", start: BED + 120 * MIN, end: BED + 145 * MIN }];
const night = (more: Record<string, unknown> = {}) => ({ source: "com.apple.health.watch", start: BED, end: NOW, asleepAt: BED + 15 * MIN,
  wokeAt: NOW - 5 * MIN, asleep: 440, core: 245, deep: 75, rem: 110, awake: 25, stages: steps, ...more });
const send = (nights: object[], who = phone) => call(who, "POST", "nights", { nights });
const logged = (kind: string) => rows("relay_outbox").filter(row => row.kind === kind).map(row => row.ref);
const workout = (more: Record<string, unknown> = {}) => ({ type: "workout", start: NOW - 40 * MIN, end: NOW - 8 * MIN, value: 32, unit: "min",
  source: "watch", ...more });
const health = (samples: object[]) => call(phone, "POST", "health", { samples });
const ticked = () => db.sql.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at)
  VALUES ('fit', 'Health database', 'https://db.example.com/relay', 'whsec_dGVzdC1vbmx5LXNlY3JldC1mb3ItdGhlLXNlbmRlcg==', '["notes","health"]', 0, ?),
  ('notes', 'Notes only', 'https://notes.example.com/relay', 'whsec_BBBB', '["notes"]', 0, ?)`).run(NOW, NOW);

afterEach(() => vi.unstubAllGlobals());

it("stores each night once with its timeline, wakes only a webhook ticked for Health, and a resend adds and logs nothing", async () => {
  ticked();
  expect(await send([night()])).toEqual({ status: 200, json: { received: 1, changed: 1 } });
  expect(queue.sent).toEqual([{ webhook: "fit", person: expect.any(String) }]);
  queue.sent = [];
  expect(await send([night()])).toEqual({ status: 200, json: { received: 1, changed: 0 } });
  expect(queue.sent).toEqual([]);
  expect(logged("night")).toHaveLength(1);
  const [row] = rows("relay_nights");
  expect(row).toMatchObject({ source: "com.apple.health.watch", start_at: BED, end_at: NOW, asleep_at: BED + 15 * MIN, asleep: 440, deep: 75 });
  expect(JSON.parse(String(row.stages))).toEqual(steps);
});

it("changes a night that grew or whose timeline changed, and logs each change once", async () => {
  await send([night()]);
  expect((await send([night({ end: NOW + 10 * MIN, wokeAt: NOW })])).json).toEqual({ received: 1, changed: 1 });
  const longer = [...steps, { stage: "awake", start: BED + 145 * MIN, end: BED + 150 * MIN }];
  expect((await send([night({ end: NOW + 10 * MIN, wokeAt: NOW, stages: longer })])).json).toEqual({ received: 1, changed: 1 });
  expect((await send([night({ end: NOW + 10 * MIN, wokeAt: NOW, stages: longer })])).json).toEqual({ received: 1, changed: 0 });
  expect(logged("night")).toHaveLength(3);
  // A night with no stages, such as a phone's bedtime, keeps an empty timeline.
  await send([night({ source: "phone", asleepAt: undefined, wokeAt: undefined, asleep: 0, core: 0, deep: 0, rem: 0, awake: 0, stages: [] })]);
  expect(rows("relay_nights").map(row => [row.source, row.asleep_at, row.stages])).toEqual([
    ["com.apple.health.watch", BED + 15 * MIN, JSON.stringify(longer)], ["phone", null, "[]"]]);
});

it("sends a changed night once, as it is now, in one health.nights message", async () => {
  const sent: { type: string; data: { nights: { end: string; minutes: { deep: number }; stages: unknown[] }[] } }[] = [];
  vi.stubGlobal("fetch", vi.fn(async (_url: string, init: RequestInit) => {
    sent.push(JSON.parse(String(init.body)));
    return new Response(null, { status: 204 });
  }));
  ticked();
  await send([night()]);
  await send([night({ end: NOW + 10 * MIN })]);
  const message = { body: queue.sent[0], ack: vi.fn(), retry: vi.fn() };
  await consume({ queue: "relay-everything-webhooks", messages: [message] } as unknown as MessageBatch, env());
  expect(message.ack).toHaveBeenCalledOnce();
  expect(sent.map(item => [item.type, item.data.nights.map(({ end, minutes, stages }) => [end, minutes.deep, stages.length])])).toEqual([
    ["health.nights", [[new Date(NOW + 10 * MIN).toISOString(), 75, 3]]]]);
});

it("refuses a bad night, a timeline over 400 steps and a person's session", async () => {
  const step = { stage: "core", start: BED, end: BED + MIN };
  for (const nights of [[], [night({ end: BED - 1 })], [night({ start: BED / 1000 })], [night({ source: "" })], [night({ deep: -1 })],
    [night({ stages: [{ ...step, stage: "in_bed" }] })], [night({ stages: [{ ...step, end: BED - 1 }] })], [night({ stages: Array(401).fill(step) })],
    [night({ stages: undefined })], [night({ score: 80 })], Array(501).fill(night())]) {
    expect((await send(nights)).status, JSON.stringify(nights).slice(0, 80)).toBe(400);
  }
  expect((await send([night({ stages: Array(400).fill(step) })])).status).toBe(200);
  expect((await send([night()], matthew)).status).toBe(403);
});

it("keeps Ben's nights in his space: his night at Ana's start never touches hers", async () => {
  await send([night()]);
  expect((await send([night({ deep: 30 })], benPhone)).json.changed).toBe(1);
  expect(rows("relay_nights").map(row => row.deep)).toEqual([75]);
  expect(rows("relay_nights", BEN).map(row => row.deep)).toEqual([30]);
});

it("stores a workout's kind, distance and calories, and refuses them on any other type", async () => {
  expect((await health([workout({ kind: "running", distance: 5100, calories: 410 })])).json).toEqual({ received: 1, added: 1 });
  expect(rows("relay_health").map(({ kind, distance, calories }) => ({ kind, distance, calories })))
    .toEqual([{ kind: "running", distance: 5100, calories: 410 }]);
  for (const wrong of [{ type: "steps", kind: "running" }, { type: "sleep", distance: 1 }, { type: "heart_rate", calories: 1 }]) {
    expect((await health([workout(wrong)])).status, JSON.stringify(wrong)).toBe(400);
  }
  for (const wrong of [{ kind: "" }, { kind: "x".repeat(61) }, { distance: -1 }, { calories: 2e6 }]) {
    expect((await health([workout(wrong)])).status, JSON.stringify(wrong)).toBe(400);
  }
});

it("fills an old workout's details once, logs it once, and counts no new row", async () => {
  ticked();
  await health([workout()]);
  queue.sent = [];
  expect((await health([workout({ kind: "running", distance: 5100, calories: 410 })])).json).toEqual({ received: 1, added: 0 });
  expect(queue.sent).toEqual([{ webhook: "fit", person: expect.any(String) }]);
  queue.sent = [];
  expect((await health([workout({ kind: "walking", distance: 1, calories: 1 })])).json).toEqual({ received: 1, added: 0 });
  expect(queue.sent).toEqual([]);
  expect(rows("relay_health").map(({ kind, distance, calories }) => ({ kind, distance, calories })))
    .toEqual([{ kind: "running", distance: 5100, calories: 410 }]);
  expect(logged("health")).toEqual(["1", "1"]);
});
