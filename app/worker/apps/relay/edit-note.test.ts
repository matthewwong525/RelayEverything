import { expect, it } from "vitest";
import { handleApp } from "../index";
import { call, checker, env, ipad, laptop, lost, matthew, NOW, phone, request, rows } from "../../../tests/relay";

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
