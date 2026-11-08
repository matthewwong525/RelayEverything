import { expect, it } from "vitest";
import { handleApp } from "../index";
import { ANA, benPhone, bucket, call, env, laptop, matthew, NOW, phone, ipad, request, rows, type Who } from "../../../tests/relay";

const PDF = new TextEncoder().encode("%PDF-1.7 warranty");
const PNG = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
const files = [{ id: "file-pdf-0001", name: "warranty.pdf", type: "application/pdf", size: PDF.byteLength },
  { id: "file-png-0001", name: "receipt.png", type: "image/png", size: PNG.byteLength }];
const note = (more: Record<string, unknown> = {}) =>
  call(phone, "POST", "notes", { clientId: "note-files-01", text: "Receipt for the desk lamp", createdAt: NOW - 60_000, attachments: files, ...more });

/** POST attachments as `who`, with the file's bytes as the body. */
const upload = (who: Who, id: string, bytes: Uint8Array | undefined, noteClientId = "note-files-01", type = "application/pdf") =>
  handleApp(request(who, "POST", "https://relay.example.com/apps/relay/api/attachments", { body: bytes,
    headers: { "Content-Type": type, "X-Note-Client-Id": noteClientId, "X-Attachment-Id": id } }), env(), null);
const open = (who: Who, id: string) => handleApp(request(who, "GET", `https://relay.example.com/apps/relay/api/attachment?id=${id}`), env(), null);
const timelineFiles = async () => (await call(matthew, "GET", "timeline")).json.notes[0].attachments;

it("stores a note's files with the note, once, however often the phone sends it", async () => {
  expect((await note()).json).toMatchObject({ added: true });
  expect((await note()).json).toMatchObject({ added: false });
  const [stored] = rows("relay_notes");
  expect(rows("relay_attachments")).toEqual([
    expect.objectContaining({ id: "file-pdf-0001", note_id: stored.id, name: "warranty.pdf", content_type: "application/pdf", size: PDF.byteLength, file_key: null }),
    expect.objectContaining({ id: "file-png-0001", note_id: stored.id, name: "receipt.png", content_type: "image/png", file_key: null })]);
});

it("takes a note of files with no words, and refuses an empty note, an eleventh file or a file over 25 MB", async () => {
  expect((await note({ text: "" })).status).toBe(200);
  expect((await note({ clientId: "note-empty-01", text: " ", attachments: [] })).status).toBe(400);
  const eleven = Array.from({ length: 11 }, (_, index) => ({ ...files[0], id: `file-many-${String(index).padStart(2, "0")}` }));
  expect((await note({ clientId: "note-many-01", attachments: eleven })).status).toBe(400);
  expect((await note({ clientId: "note-big-01", attachments: [{ ...files[0], size: 25 * 1024 * 1024 + 1 }] })).status).toBe(400);
  expect((await note({ clientId: "note-twice-01", attachments: [files[0], files[0]] })).status).toBe(400);
  expect(rows("relay_notes")).toHaveLength(1);
});

it("keeps a file of a type it can't read as plain bytes", async () => {
  await note({ attachments: [{ ...files[0], type: "" }, { ...files[1], type: "image/png\r\nX-Evil: 1" }] });
  expect(rows("relay_attachments").map(row => row.content_type)).toEqual(["application/octet-stream", "application/octet-stream"]);
});

it("seals each listed file once, shows it as waiting until it comes, and opens it for its person", async () => {
  await note();
  expect(await timelineFiles()).toEqual([{ ...files[0], ready: false }, { ...files[1], ready: false }]);
  expect(await (await upload(phone, "file-pdf-0001", PDF)).json()).toEqual({ ok: true, added: true });
  expect(await (await upload(phone, "file-pdf-0001", PDF)).json()).toEqual({ ok: true, added: false });
  expect(bucket.put).toHaveBeenCalledOnce();
  const name = `people/${ANA}/attachments/file-pdf-0001`;
  expect(rows("relay_attachments")[0].file_key).toBe(name);
  expect(Buffer.from(bucket.objects.get(name)!).includes(Buffer.from(PDF))).toBe(false);
  expect(await timelineFiles()).toEqual([{ ...files[0], ready: true }, { ...files[1], ready: false }]);

  const pdf = await open(matthew, "file-pdf-0001");
  expect(pdf.status).toBe(200);
  expect(new Uint8Array(await pdf.arrayBuffer())).toEqual(PDF);
  expect(Object.fromEntries(pdf.headers)).toMatchObject({ "content-type": "application/pdf", "x-content-type-options": "nosniff",
    "content-disposition": `attachment; filename="warranty.pdf"; filename*=UTF-8''warranty.pdf` });
  await upload(phone, "file-png-0001", PNG, "note-files-01", "image/png");
  expect((await open(matthew, "file-png-0001")).headers.get("content-disposition")).toMatch(/^inline; /);
  // A waiting file, an unknown one or a bad id opens nothing.
  expect((await open(matthew, "file-none-0001")).status).toBe(404);
  expect((await open(matthew, "../x")).status).toBe(400);
  // The person's phones open it too, to sync; a chat key can't, and another person's phone finds nothing.
  for (const who of [phone, ipad]) expect(new Uint8Array(await (await open(who, "file-pdf-0001")).arrayBuffer())).toEqual(PDF);
  expect((await open(laptop, "file-pdf-0001")).status).toBe(403);
  expect((await open(benPhone, "file-pdf-0001")).status).toBe(404);
});

it("refuses a file its note does not list, one on another device's note, and one over 25 MB", async () => {
  await note();
  expect((await upload(phone, "file-other-01", PDF)).status).toBe(404);
  expect((await upload(phone, "file-pdf-0001", PDF, "note-other-01")).status).toBe(404);
  expect((await upload(ipad, "file-pdf-0001", PDF)).status).toBe(404);
  expect((await upload(phone, "bad id", PDF)).status).toBe(400);
  expect((await upload(phone, "file-pdf-0001", new Uint8Array(25 * 1024 * 1024 + 1))).status).toBe(413);
  expect(rows("relay_attachments").every(row => row.file_key === null)).toBe(true);
  expect(bucket.objects.size).toBe(0);
});

it("names a download safely in both header forms, and takes an empty file or a call with no file named", async () => {
  await note({ attachments: [{ id: "file-odd-0001", name: "Ana's café (1).txt", type: "text/plain", size: 0 }] });
  expect((await upload(phone, "file-odd-0001", undefined)).status).toBe(200);
  expect((await open(matthew, "file-odd-0001")).headers.get("content-disposition"))
    .toBe(`attachment; filename="Ana's caf_ (1).txt"; filename*=UTF-8''Ana%27s%20caf%C3%A9%20%281%29.txt`);
  const bare = await handleApp(request(phone, "POST", "https://relay.example.com/apps/relay/api/attachments", { body: PDF }), env(), null);
  expect(bare.status).toBe(400);
  expect((await handleApp(request(matthew, "GET", "https://relay.example.com/apps/relay/api/attachment"), env(), null)).status).toBe(400);
});
