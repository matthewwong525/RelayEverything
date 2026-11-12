import { expect, it } from "vitest";
import { benPhone, call, checker, ipad, laptop, lost, matthew, NOW, phone, rows } from "../../../tests/relay";

const MINUTE = 60_000;
const sent = () => call(phone, "POST", "notes", { clientId: "note-pin-01", text: "Door code", createdAt: NOW - 5 * MINUTE });
const pin = (who: Parameters<typeof call>[0], more: Record<string, unknown> = {}) =>
  call(who, "PUT", "notes/pin", { clientId: "note-pin-01", pinned: true, ...more });
const pins = () => rows("relay_notes").map(row => [row.pinned_at, row.pin_changed_at]);
const log = () => rows("relay_outbox").map(row => row.kind);

it("pins a phone's own note by clientId and unpins it, keeping its words and time, and logs nothing", async () => {
  const { json: { id } } = await sent();
  expect(await pin(phone, { at: NOW - MINUTE })).toEqual({ status: 200, json: { id, pinned: true, pinChangedAt: NOW - MINUTE, updated: true } });
  expect(pins()).toEqual([[NOW - MINUTE, NOW - MINUTE]]);
  expect(await pin(phone, { pinned: false })).toEqual({ status: 200, json: { id, pinned: false, pinChangedAt: NOW, updated: true } });
  expect(pins()).toEqual([[null, NOW]]);
  expect(rows("relay_notes").map(row => [row.text, row.edited_at, row.recorded_at])).toEqual([["Door code", null, NOW - 5 * MINUTE]]);
  expect(log()).toEqual(["note.created"]);
});

it("pins any note in the space by id, from another phone or the page, and changes nothing when already pinned", async () => {
  const { json: { id } } = await sent();
  expect((await call(ipad, "PUT", "notes/pin", { id, pinned: true })).json).toEqual({ id, pinned: true, pinChangedAt: NOW, updated: true });
  expect((await call(matthew, "PUT", "notes/pin", { id, pinned: true })).json).toEqual({ id, pinned: true, pinChangedAt: NOW, updated: false });
  expect(pins()).toEqual([[NOW, NOW]]);
  expect(await call(matthew, "PUT", "notes/pin", { id, pinned: false })).toMatchObject({ status: 200, json: { pinned: false } });
});

it("refuses a pin change older than the note's last one, so the newer change wins", async () => {
  await sent();
  await pin(phone, { at: NOW - MINUTE });
  expect(await pin(phone, { pinned: false, at: NOW - 2 * MINUTE })).toMatchObject({ status: 409, json: { error: { code: "older" } } });
  expect(pins()).toEqual([[NOW - MINUTE, NOW - MINUTE]]);
  // A phone clock set ahead counts as now, and the answer gives the server's time for the phone to keep.
  expect((await pin(phone, { pinned: false, at: NOW + 60 * MINUTE })).json).toMatchObject({ pinChangedAt: NOW, updated: true });
  expect(pins()).toEqual([[null, NOW]]);
});

it("keeps the newer time of a pin that matches the note's, so an older change made elsewhere still loses", async () => {
  await sent();
  await pin(phone, { at: NOW - 3 * MINUTE });
  expect((await pin(ipad, { clientId: undefined, id: rows("relay_notes")[0].id, at: NOW - MINUTE })).json)
    .toMatchObject({ pinned: true, pinChangedAt: NOW - MINUTE, updated: false });
  expect(pins()).toEqual([[NOW - 3 * MINUTE, NOW - MINUTE]]);
  expect(await pin(phone, { pinned: false, at: NOW - 2 * MINUTE })).toMatchObject({ status: 409, json: { error: { code: "older" } } });
  expect(pins()).toEqual([[NOW - 3 * MINUTE, NOW - MINUTE]]);
  expect(log()).toEqual(["note.created"]);
});

it("refuses a key that is not a phone's, another person's phone, an unknown note, and both or neither id", async () => {
  const { json: { id } } = await sent();
  for (const who of [laptop, lost, checker]) expect((await pin(who)).status, JSON.stringify(who)).toBe(403);
  expect((await pin(null)).status).toBe(401);
  expect((await call(benPhone, "PUT", "notes/pin", { id, pinned: true })).status).toBe(404);
  expect((await pin(ipad)).status).toBe(404);
  expect((await pin(phone, { id })).status).toBe(400);
  expect((await call(phone, "PUT", "notes/pin", { pinned: true })).status).toBe(400);
  expect(pins()).toEqual([[null, null]]);
});
