import { expect, it } from "vitest";
import { BEN, call, db, NOW, phone, benPhone, queue, rows } from "../../../tests/relay";

const HOUR = 3_600_000;
const event = (key: string, more: Record<string, unknown> = {}) => ({ key, calendar: "Work", title: `Meeting ${key}`, start: NOW, end: NOW + HOUR,
  allDay: false, people: [{ name: "Sam Lee", email: "sam@example.com", organizer: true }], ...more });
const send = (events: object[], removed: string[] = [], who = phone) => call(who, "POST", "calendar", { events, removed });
const outbox = () => rows("relay_outbox").filter(row => row.kind === "calendar").map(row => row.ref);
const events = (person?: string) => rows("relay_calendar_events", person).map(row =>
  ({ key: row.event_key, title: row.title, start: row.start_at, removed: row.removed_at !== null, people: JSON.parse(row.people as string) }));

it("stores each event once, and a resend changes nothing and wakes no webhook", async () => {
  db.sql.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at)
    VALUES ('cal', 'Calendar database', 'https://db.example.com/relay', 'whsec_AAAA', '["notes","calendar"]', 0, ?)`).run(NOW);
  const week = [event("w:1:1"), event("w:2:2", { start: NOW + 2 * HOUR, end: NOW + 3 * HOUR, location: "Office", notes: "Bring samples." })];
  expect(await send(week)).toEqual({ status: 200, json: { received: 2, changed: 2, removed: 0 } });
  expect(queue.sent).toEqual([{ webhook: "cal", person: expect.any(String) }]);
  queue.sent = [];
  expect(await send(week)).toEqual({ status: 200, json: { received: 2, changed: 0, removed: 0 } });
  expect(queue.sent).toEqual([]);
  expect(outbox()).toHaveLength(2);
  expect(events()).toEqual([
    { key: "w:1:1", title: "Meeting w:1:1", start: NOW, removed: false, people: [{ name: "Sam Lee", email: "sam@example.com", organizer: true }] },
    { key: "w:2:2", title: "Meeting w:2:2", start: NOW + 2 * HOUR, removed: false, people: [{ name: "Sam Lee", email: "sam@example.com", organizer: true }] }]);
});

it("changes a moved event, marks a removed one, and brings it back when the phone sends it again", async () => {
  await send([event("w:1:1"), event("w:2:2")]);
  expect(await send([event("w:1:1", { title: "Moved meeting", end: NOW + 2 * HOUR })], ["w:2:2", "w:9:9"]))
    .toEqual({ status: 200, json: { received: 1, changed: 1, removed: 1 } });
  expect(events().map(({ key, title, removed }) => [key, title, removed])).toEqual([["w:1:1", "Moved meeting", false], ["w:2:2", "Meeting w:2:2", true]]);
  expect((await send([], ["w:2:2"])).json).toEqual({ received: 0, changed: 0, removed: 0 });
  expect((await send([event("w:2:2")])).json.changed).toBe(1);
  expect(events()[1].removed).toBe(false);
  // Two first stores, the move, the removal and the return: each one log entry.
  expect(outbox()).toHaveLength(5);
});

it("refuses an empty send, a bad event, a person's session and too many events", async () => {
  for (const body of [{ events: [], removed: [] }, { events: [event("k", { end: NOW - 1 })], removed: [] }, { events: [event("k", { start: NOW / 1000 })], removed: [] },
    { events: [event("k", { title: "x".repeat(501) })], removed: [] }, { events: Array(201).fill(event("k")), removed: [] },
    { events: [{ ...event("k"), color: "red" }], removed: [] }]) {
    expect((await call(phone, "POST", "calendar", body)).status, JSON.stringify(body).slice(0, 80)).toBe(400);
  }
  expect(rows("relay_calendar_events")).toEqual([]);
});

it("keeps Ben's events in his space: his key with Ana's event key never touches hers", async () => {
  await send([event("w:1:1")]);
  expect((await send([event("w:1:1", { title: "Ben's" })], [], benPhone)).json.changed).toBe(1);
  expect((await send([], ["w:1:1"], benPhone)).json.removed).toBe(1);
  expect(events().map(({ title, removed }) => [title, removed])).toEqual([["Meeting w:1:1", false]]);
  expect(events(BEN).map(({ title, removed }) => [title, removed])).toEqual([["Ben's", true]]);
});
