import { expect, it } from "vitest";
import { benPhone, call, ipad, laptop, matthew, NOW, phone, rows } from "../../../tests/relay";

const MINUTE = 60_000;
const PDF = { id: "file-pdf-0001", name: "pass.pdf", type: "application/pdf", size: 3 };
const send = (who: Parameters<typeof call>[0], index: number, more: Record<string, unknown> = {}) =>
  call(who, "POST", "notes", { clientId: `note-sync-${String(index).padStart(2, "0")}`, text: `Note ${index}`, createdAt: NOW - index * MINUTE, ...more });
type Page = { notes: { text: string; mine: boolean }[]; next: number; more: boolean };
const sync = (who: Parameters<typeof call>[0], since = 0, limit?: number) =>
  call(who, "GET", "notes", { since: String(since), ...limit && { limit: String(limit) } });
const page = async (who: Parameters<typeof call>[0], since = 0, limit?: number) =>
  (await sync(who, since, limit)).json as unknown as Page;

/** Every page from `since`, `limit` notes at a time: each page's note texts, and the last `next`. */
async function allPages(who: Parameters<typeof call>[0], since: number, limit: number) {
  const pages: string[][] = [];
  for (let more = true; more;) {
    const json = await page(who, since, limit);
    pages.push(json.notes.map(note => note.text));
    ({ next: since, more } = json);
  }
  return { pages, next: since };
}

it("gives every note once, in change order, with no repeat or gap across a page edge", async () => {
  for (const index of [1, 2, 3, 4, 5]) await send(index % 2 ? phone : ipad, index);
  const first = await allPages(phone, 0, 2);
  expect(first.pages).toEqual([["Note 1", "Note 2"], ["Note 3", "Note 4"], ["Note 5"]]);
  // Nothing new: an empty page that keeps the number.
  expect((await sync(phone, first.next)).json).toEqual({ notes: [], next: first.next, more: false });
  // A changed note comes again, once, after the new one.
  await call(ipad, "PATCH", "notes", { clientId: "note-sync-02", text: "Note 2, changed" });
  await send(phone, 6);
  expect((await allPages(phone, first.next, 1)).pages).toEqual([["Note 2, changed"], ["Note 6"]]);
});

it("gives each note's sync fields, with mine true only for the calling phone's own notes", async () => {
  await send(phone, 1, { attachments: [PDF], lat: 38.7, lon: -9.1, place: "Lisbon" });
  await send(ipad, 2);
  await call(ipad, "PATCH", "notes", { clientId: "note-sync-02", text: "Changed", editedAt: NOW - MINUTE });
  const { json } = await sync(phone);
  const [ownId, otherId] = rows("relay_notes").map(row => row.id);
  expect(json.notes).toEqual([
    { id: ownId, clientId: "note-sync-01", mine: true, source: "typed", text: "Note 1", recordedAt: NOW - MINUTE, editedAt: null,
      device: "Android phone", audio: false, place: { lat: 38.7, lon: -9.1, accuracy: null, name: "Lisbon", from: "phone" },
      attachments: [{ ...PDF, ready: false }] },
    { id: otherId, clientId: "note-sync-02", mine: false, source: "typed", text: "Changed", recordedAt: NOW - 2 * MINUTE,
      editedAt: NOW - MINUTE, device: "iPad", audio: false, place: null, attachments: [] },
  ]);
  expect((await page(ipad)).notes.map(note => note.mine)).toEqual([false, true]);
  // The page reads the same feed, and owns none of it.
  expect((await page(matthew)).notes.map(note => note.mine)).toEqual([false, false]);
});

it("gives a phone key only its own person's notes, and refuses a chat key", async () => {
  await send(phone, 1);
  await send(benPhone, 2);
  expect((await page(benPhone)).notes.map(note => note.text)).toEqual(["Note 2"]);
  expect((await page(phone)).notes.map(note => note.text)).toEqual(["Note 1"]);
  expect((await sync(laptop)).status).toBe(403);
  expect((await sync(null)).status).toBe(401);
});
