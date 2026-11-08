// The one inbox: a message from a way in, such as email, becomes one note in its person's space, from that way's own
// device, with its files sealed as a phone's are. A later way in calls it too. wiki/relay-spaces.md#ways-in
import { addNote } from "../add-note.ts";
import { storeFile } from "../attachments.ts";
import { MAX_FILE_BYTES, MAX_FILES, typeOf } from "../notes.ts";
import { spaceOf, type Caller, type PersonSpace, type SpaceEnv } from "../space.ts";
import { wake } from "../webhooks/send.ts";

export type InboxFile = { name: string; type: string; bytes: Uint8Array };
/** One message: `id` is unique for the message, so a repeat stores once; `left` names files already left out. */
export type InboxItem = { channel: "email"; id: string; sentAt: number; text: string; files: InboxFile[]; left?: string[] };
export type ReceiveEnv = SpaceEnv & Parameters<typeof wake>[0];

/** Each way in's device in the space: its notes name it, so the page, webhooks and AI show where a note came from. */
const DEVICES = { email: { name: "Email", token: "inbox:email" } };
const MAX_TEXT = 20_000;
const NAMED = 20;

/** The message within the note limits, up to 10 files of 25 MB each; each file left out is named in `left`. */
export function fitted(item: InboxItem): InboxItem & { left: string[] } {
  const files: InboxFile[] = [];
  const left = [...item.left ?? []];
  for (const file of item.files) {
    if (file.bytes.byteLength > MAX_FILE_BYTES) left.push(`${file.name} (larger than 25 MB)`);
    else if (files.length >= MAX_FILES) left.push(`${file.name} (more than 10 files)`);
    else files.push(file);
  }
  return { ...item, files, left };
}

/** The note's words: the message, then the files left out, the first 20 by name. */
function textOf({ text, left }: { text: string; left: string[] }): string {
  if (!left.length) return text.slice(0, MAX_TEXT);
  const more = left.length > NAMED ? `, and ${left.length - NAMED} more` : "";
  const named = `Left out: ${left.slice(0, NAMED).join(", ")}${more}.`;
  return `${text.slice(0, MAX_TEXT - named.length - 2)}\n\n${named}`.trim();
}

/** The way in's own device in the space, made on its first message. */
async function deviceOf(space: PersonSpace, channel: InboxItem["channel"]): Promise<string> {
  const { name, token } = DEVICES[channel];
  const row = await space.db.prepare(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches)
    VALUES (?, ?, ?, '', ?, NULL, 'inbox') ON CONFLICT (token_client_id) DO UPDATE SET token_id = excluded.token_id RETURNING id`)
    .bind(crypto.randomUUID(), name, token, Date.now()).first<{ id: string }>();
  return row!.id;
}

/** Stores the message as one note, once per way in and message id, then seals each of its files not stored yet. */
export async function receive(env: ReceiveEnv, caller: Caller, item: InboxItem) {
  const space = spaceOf(env, caller);
  const fit = fitted(item);
  const deviceId = await deviceOf(space, fit.channel);
  // A file's id comes from the message's, so a repeat names the same files.
  const files = fit.files.map((file, index) => ({ id: `${fit.id.slice(0, 32)}-${index}`, name: (file.name.trim() || "attachment").slice(0, 255),
    type: typeOf(file.type), size: file.bytes.byteLength, bytes: file.bytes }));
  const note = await addNote(env, space, deviceId, { clientId: `${fit.channel}:${fit.id}`, text: textOf(fit), createdAt: fit.sentAt,
    attachments: files.map(({ bytes: _bytes, ...file }) => file) });
  const { results } = await space.db.prepare("SELECT id FROM relay_attachments WHERE note_id = ? AND file_key IS NULL").bind(note.id).all<{ id: string }>();
  const waiting = new Set(results.map(row => row.id));
  for (const file of files) if (waiting.has(file.id)) await storeFile(space, file.id, file.bytes.slice().buffer);
  // Each seal logs a note.file, which goes to every webhook with the note.
  if (waiting.size) await wake(env, space, ["notes"]);
  return note;
}
