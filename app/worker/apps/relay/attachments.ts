// POST attachments: a note's file, its raw bytes sent by the phone after the note that lists it, sealed into the
// person's folder once per file. GET attachment?id=: the file, opened for its signed-in person, for the page.
import { boundedBytes } from "../../api/body.ts";
import type { ActionCall } from "../../api/contract.ts";
import { asDevice, asPerson } from "./caller.ts";
import { CLIENT_ID, MAX_FILE_BYTES } from "./notes.ts";
import type { PersonSpace } from "./space.ts";
import { refused, type Env } from "./store.ts";
import { wake } from "./webhooks/send.ts";

type Call = Pick<ActionCall, "url" | "identity">;
type Listed = { id: string; file_key: string | null };

const notFound = () => Response.json({ error: "Not found" }, { status: 404 });

export const attachmentAdd: (request: Request, env: Env, call: Call) => Promise<Response> =
  asDevice<Call>("Only a Relay Everything device key can send files", async ({ space, device, request, env }) => {
    const noteClientId = request.headers.get("X-Note-Client-Id") ?? "";
    const id = request.headers.get("X-Attachment-Id") ?? "";
    if (!CLIENT_ID.test(noteClientId) || !CLIENT_ID.test(id)) return refused(400, "Name the file and its note: X-Note-Client-Id and X-Attachment-Id.");
    // The file must be listed on a note this device sent: a device adds files only to its own notes.
    const listed = await space.db.prepare(`SELECT a.id, a.file_key FROM relay_attachments a JOIN relay_notes n ON n.id = a.note_id
      WHERE a.id = ? AND n.device_id = ? AND n.client_id = ?`).bind(id, device.id, noteClientId).first<Listed>();
    if (!listed) return notFound();
    if (listed.file_key) return Response.json({ ok: true, added: false });
    let bytes: Uint8Array;
    try {
      bytes = await boundedBytes(request.body ?? new Blob().stream(), MAX_FILE_BYTES, () => new Error("too large"));
    } catch {
      return refused(413, "The file is larger than 25 MB");
    }
    // boundedBytes gives a new array of exactly the file's size, so its buffer is the file.
    await storeFile(space, id, bytes.buffer as ArrayBuffer);
    // The seal logs a note.file, which goes to every webhook with the note.
    await wake(env, space, ["notes"]);
    return Response.json({ ok: true, added: true });
  });

/** Seals a listed file into the person's folder and marks it ready: the phone's upload and the inbox share it. */
export async function storeFile(space: PersonSpace, id: string, bytes: ArrayBuffer) {
  const key = await space.files.put(`attachments/${id}`, bytes);
  // Two uploads of one file at once seal the same bytes under the same name, so the second changes nothing.
  await space.db.prepare("UPDATE relay_attachments SET file_key = ?, size = ? WHERE id = ? AND file_key IS NULL").bind(key, bytes.byteLength, id).run();
}

type Stored = { name: string; content_type: string; file_key: string | null };

/** `inline` for a picture, which the page shows; every other file downloads under its own name. */
function disposition(type: string, name: string): string {
  const plain = name.replace(/[^\x20-\x7e]|["\\]/g, "_");
  const encoded = encodeURIComponent(name).replace(/['()*]/g, letter => `%${letter.charCodeAt(0).toString(16).toUpperCase()}`);
  return `${type.startsWith("image/") ? "inline" : "attachment"}; filename="${plain}"; filename*=UTF-8''${encoded}`;
}

export const attachment: (request: Request, env: Env, call: Call) => Promise<Response> = asPerson<Call>(async ({ space, call }) => {
  const id = call.url.searchParams.get("id") ?? "";
  if (!CLIENT_ID.test(id)) return refused(400, "Give a file's id");
  const row = await space.db.prepare("SELECT name, content_type, file_key FROM relay_attachments WHERE id = ?").bind(id).first<Stored>();
  const data = row?.file_key ? await space.files.open(row.file_key) : null;
  if (!row || !data) return notFound();
  // A file's type comes from the phone, so the browser must not guess another or run it as the page's own.
  return new Response(data, { headers: { "Content-Type": row.content_type, "Content-Length": String(data.byteLength),
    "Content-Disposition": disposition(row.content_type, row.name), "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "sandbox; default-src 'none'; img-src 'self'; style-src 'unsafe-inline'", "Cache-Control": "private, max-age=3600" } });
});
