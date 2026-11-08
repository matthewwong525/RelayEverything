import { expect, it, vi } from "vitest";
import { handleApp } from "../index";
import { benPhone, call, checker, db, env, ipad, laptop, lost, matthew, NOW, phone, request, rows } from "../../../tests/relay";

const MINUTE = 60_000;
const PDF = { id: "file-pdf-0001", name: "warranty.pdf", type: "application/pdf", size: 3 };
const sent = (more: Record<string, unknown> = {}) =>
  call(phone, "POST", "notes", { clientId: "note-edit-01", text: "Desk lamp", createdAt: NOW - 5 * MINUTE, ...more });
const edit = (who: Parameters<typeof call>[0], more: Record<string, unknown> = {}) =>
  call(who, "PATCH", "notes", { clientId: "note-edit-01", text: "# Desk lamp\n- [x] Receipt\n- [ ] Bulb", ...more });
const log = () => rows("relay_outbox").map(row => [row.kind, row.ref, row.at]);

it("keeps a sent note's new words and the time of the change, and logs one note.updated after its note.created", async () => {
  const { json: { id } } = await sent();
  expect(await edit(phone)).toEqual({ status: 200, json: { id, updated: true } });
  expect(rows("relay_notes").map(row => [row.text, row.edited_at])).toEqual([["# Desk lamp\n- [x] Receipt\n- [ ] Bulb", NOW]]);
  expect(log()).toEqual([["note.created", id, NOW - 5 * MINUTE], ["note.updated", id, NOW - 5 * MINUTE]]);
  // The page reads the new words.
  expect((await call(matthew, "GET", "timeline")).json.notes[0].text).toBe("# Desk lamp\n- [x] Receipt\n- [ ] Bulb");
});

it("changes nothing and logs nothing for the same words and no new file", async () => {
  await sent({ attachments: [PDF] });
  expect((await edit(phone, { text: "Desk lamp", attachments: [PDF] })).json).toMatchObject({ updated: false });
  expect(rows("relay_notes").map(row => row.edited_at)).toEqual([null]);
  expect(log().map(([kind]) => kind)).toEqual(["note.created"]);
});

it("lists a file added with the change, never drops one, and takes its bytes after", async () => {
  await sent({ attachments: [PDF] });
  const added = { ...PDF, id: "file-png-0001", name: "bulb.png", type: "IMAGE/PNG" };
  expect((await edit(phone, { text: "Desk lamp", attachments: [added] })).json).toMatchObject({ updated: true });
  expect(rows("relay_attachments").map(row => [row.id, row.content_type])).toEqual([["file-pdf-0001", "application/pdf"], ["file-png-0001", "image/png"]]);
  expect(log().map(([kind]) => kind)).toEqual(["note.created", "note.updated"]);
  const upload = await handleApp(request(phone, "POST", "https://relay.example.com/apps/relay/api/attachments", { body: new Uint8Array([1, 2, 3]),
    headers: { "Content-Type": "image/png", "X-Note-Client-Id": "note-edit-01", "X-Attachment-Id": "file-png-0001" } }), env(), null);
  expect(await upload.json()).toEqual({ ok: true, added: true });
});

it("refuses another device's note or an unknown one, and leaves the note as it was", async () => {
  await sent();
  expect(await edit(ipad)).toMatchObject({ status: 404, json: { error: { code: "not_found" } } });
  expect((await edit(phone, { clientId: "note-unknown-01" })).status).toBe(404);
  expect((await edit(phone, { text: " " })).status).toBe(400);
  expect(rows("relay_notes").map(row => [row.text, row.edited_at])).toEqual([["Desk lamp", null]]);
  expect(log().map(([kind]) => kind)).toEqual(["note.created"]);
});

it("takes a change only from a phone's device key", async () => {
  await sent();
  for (const who of [matthew, laptop, lost, checker, null]) expect(await edit(who), JSON.stringify(who)).toMatchObject({ status: 403 });
  expect(rows("relay_notes").map(row => row.text)).toEqual(["Desk lamp"]);
});

/** An emailed note in Ana's space, from her Email device. */
const emailed = () => db.sql.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches)
    VALUES ('d-mail', 'Email', 'inbox:email', '', ${NOW}, 'inbox');
  INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at)
    VALUES ('n-mail', 'd-mail', 'typed', 'email:m-1', 'Flight to Lisbn', ${NOW - 60 * MINUTE}, ${NOW - 60 * MINUTE})`);
const byId = (who: Parameters<typeof call>[0], more: Record<string, unknown> = {}) =>
  call(who, "PATCH", "notes", { id: "n-mail", text: "Flight to Lisbon", ...more });

it("changes any note in the space by id, from any phone, and logs one note.updated", async () => {
  emailed();
  expect(await byId(phone, { editedAt: NOW - MINUTE })).toEqual({ status: 200, json: { id: "n-mail", updated: true } });
  expect(rows("relay_notes").map(row => [row.id, row.text, row.edited_at])).toEqual([["n-mail", "Flight to Lisbon", NOW - MINUTE]]);
  expect(log()).toEqual([["note.created", "n-mail", NOW - 60 * MINUTE], ["note.updated", "n-mail", NOW - 60 * MINUTE]]);
  // The other phone changes it again; the page reads its words.
  expect((await byId(ipad, { text: "Flight to Lisbon, seat 14A" })).json).toEqual({ id: "n-mail", updated: true });
  expect((await call(matthew, "GET", "timeline")).json.notes[0].text).toBe("Flight to Lisbon, seat 14A");
  expect(log().map(([kind]) => kind)).toEqual(["note.created", "note.updated", "note.updated"]);
});

it("refuses a change older than the note's last one, keeps the newer words, and logs nothing", async () => {
  emailed();
  await byId(ipad, { text: "Pixel's words", editedAt: NOW - 30 * MINUTE });
  const older = await byId(phone, { text: "iPhone's words", editedAt: NOW - 60 * MINUTE + 1 });
  expect(older.status).toBe(409);
  expect(older.json).toMatchObject({ error: { code: "older" } });
  // The phone's next sync gives it the newer words.
  expect((await call(phone, "GET", "notes")).json.notes).toMatchObject([{ id: "n-mail", text: "Pixel's words", editedAt: NOW - 30 * MINUTE,
    mine: false, clientId: "email:m-1", device: "Email" }]);
  expect(rows("relay_notes").map(row => row.text)).toEqual(["Pixel's words"]);
  expect(log().map(([kind]) => kind)).toEqual(["note.created", "note.updated"]);
});

it("takes a change from a phone clock set ahead as made now, so a later change still wins", async () => {
  emailed();
  await byId(phone, { editedAt: NOW + 24 * 60 * MINUTE });
  expect(rows("relay_notes").map(row => row.edited_at)).toEqual([NOW]);
  vi.setSystemTime(NOW + MINUTE);
  expect((await byId(ipad, { text: "Later words" })).json).toMatchObject({ updated: true });
  expect(rows("relay_notes").map(row => [row.text, row.edited_at])).toEqual([["Later words", NOW + MINUTE]]);
});

it("refuses a new file on another device's note, and both or neither of id and clientId", async () => {
  emailed();
  expect(await byId(phone, { attachments: [PDF] })).toMatchObject({ status: 400, json: { error: { code: "not_own" } } });
  expect((await byId(phone, { clientId: "note-edit-01" })).status).toBe(400);
  expect((await call(phone, "PATCH", "notes", { text: "No note named" })).status).toBe(400);
  expect((await byId(phone, { id: "n-unknown" })).status).toBe(404);
  expect(rows("relay_attachments")).toEqual([]);
  expect(log().map(([kind]) => kind)).toEqual(["note.created"]);
});

it("refuses a phone key from another person's space by id", async () => {
  emailed();
  expect((await byId(benPhone)).status).toBe(404);
  expect(rows("relay_notes").map(row => row.text)).toEqual(["Flight to Lisbn"]);
});
