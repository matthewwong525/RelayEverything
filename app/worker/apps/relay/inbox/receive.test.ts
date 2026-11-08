import { expect, it } from "vitest";
import { ANA, bucket, NOW, rows } from "../../../../tests/relay";
import { inboxEnv } from "../../../../tests/relay-inbox";
import { vouch } from "../space";
import { receive, type InboxItem } from "./receive";

const PDF = new TextEncoder().encode("%PDF-1.4 receipt");
const item = (more: Partial<InboxItem> = {}): InboxItem =>
  ({ channel: "email", id: "message-id-hash-0001", sentAt: NOW - 3_600_000, text: "Fwd: Your receipt\n\nThank you.", files: [], ...more });
const send = (more?: Partial<InboxItem>) => receive(inboxEnv(), vouch("inbox", ANA, { email: "ana@example.com" }), item(more));

it("stores a message of words as one note from the Email device, at the time it was sent", async () => {
  expect(await send()).toMatchObject({ added: true });
  expect(rows("relay_devices").filter(row => row.reaches === "inbox")).toEqual([expect.objectContaining({ name: "Email",
    token_client_id: "inbox:email", revoked_at: null })]);
  const [note] = rows("relay_notes");
  expect(note).toMatchObject({ source: "typed", client_id: "email:message-id-hash-0001", text: "Fwd: Your receipt\n\nThank you.",
    recorded_at: NOW - 3_600_000 });
});

it("seals the message's files with the note, and stores a repeat once", async () => {
  const files = [{ name: "receipt.pdf", type: "application/pdf", bytes: PDF }, { name: " ", type: "text/html\r\nX-Evil: 1", bytes: PDF }];
  await send({ files });
  expect(await send({ files, text: "Changed" })).toMatchObject({ added: false });
  expect(rows("relay_notes")).toHaveLength(1);
  expect(rows("relay_devices").filter(row => row.reaches === "inbox")).toHaveLength(1);
  const stored = rows("relay_attachments");
  expect(stored.map(row => [row.name, row.content_type, row.size])).toEqual([["receipt.pdf", "application/pdf", PDF.byteLength],
    ["attachment", "application/octet-stream", PDF.byteLength]]);
  expect(stored.every(row => row.file_key === `people/${ANA}/attachments/${row.id}`)).toBe(true);
  expect(bucket.put).toHaveBeenCalledTimes(2);
  for (const key of bucket.objects.keys()) expect(Buffer.from(bucket.objects.get(key)!).includes(Buffer.from(PDF))).toBe(false);
});

it("leaves out a file over 25 MB and an eleventh file, and names them in the note", async () => {
  const big = { name: "scan.tiff", type: "image/tiff", bytes: new Uint8Array(25 * 1024 * 1024 + 1) };
  const small = Array.from({ length: 11 }, (_, index) => ({ name: `page-${index + 1}.pdf`, type: "application/pdf", bytes: PDF }));
  await send({ files: [big, ...small] });
  expect(rows("relay_attachments").map(row => row.name)).toEqual(small.slice(0, 10).map(file => file.name));
  expect(rows("relay_notes")[0].text).toBe("Fwd: Your receipt\n\nThank you.\n\nLeft out: scan.tiff (larger than 25 MB), page-11.pdf (more than 10 files).");
});

it("names only the first 20 files left out, and keeps a long message within the note limit", async () => {
  await send({ text: "x".repeat(30_000), left: Array.from({ length: 23 }, (_, index) => `f${index}.bin`) });
  const { text } = rows("relay_notes")[0] as { text: string };
  expect(text.length).toBeLessThanOrEqual(20_000);
  expect(text).toMatch(/Left out: f0\.bin, .*f19\.bin, and 3 more\.$/);
});
