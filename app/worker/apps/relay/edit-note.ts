// PATCH notes: new words or transcripts for any note in the space, by `id` or the device's `clientId`, and files
// added to or removed from a note it sent. Logs one note.updated; an older change changes nothing.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { addFiles } from "./add-note.ts";
import { asDeviceOrPage } from "./caller.ts";
import { CLIENT_ID, hasWords, MAX_FILES, noteFiles, noteText, withTypes } from "./notes.ts";
import { removeSealed } from "./recently-deleted.ts";
import type { PersonSpace } from "./space.ts";
import { time } from "./store.ts";
import { wake } from "./webhooks/send.ts";

const editInput = z.strictObject({
  id: z.string().max(64).optional().describe("The server's id for the note, as GET notes gives it: any note in your space."),
  clientId: z.string().regex(CLIENT_ID).optional().describe("Or the device's own id for a note it sent, as POST notes sent it."),
  text: noteText.describe("What the note says now, in place of its words before. It can be empty only when the note has files."),
  attachments: noteFiles.optional()
    .describe("All of the note's files now, up to 10. A file the server lacks is added: send its bytes after, with POST attachments. "
      + "A known recording takes its new transcript and length. A file left out stays: only `removed` removes one."),
  removed: z.array(z.string().regex(CLIENT_ID)).max(MAX_FILES).optional()
    .describe("The ids of files to remove from a note this device sent, up to 10: each goes from the note and from your space. "
      + "An id the note does not hold is skipped, so a resend changes nothing."),
  editedAt: time.optional().describe("When the device made the change, in Unix ms; now when left out. A later time is taken as now."),
}).refine(edit => (edit.id === undefined) !== (edit.clientId === undefined), "Give the note's id or its clientId, not both.")
  .refine(edit => hasWords(edit) || !!edit.removed?.length, "Give the note words or a file.");
type Edit = z.infer<typeof editInput>;
type Stored = { id: string; text: string; device_id: string; client_id: string | null; edited_at: number | null; deleted_at: number | null };

const REFUSAL = "Only a phone key or the Relay Everything page can change a note.";
const ERRORS = { not_found: "Your space has no note with this id, or this device sent no note with this clientId.",
  older: "The note changed after this change was made, so the newer words stay: GET notes gives them.",
  not_own: "Add or remove a file only on a note this device sent.",
  deleted: "The note is in Recently Deleted, where it can't be changed: recover it first with POST notes/recover." };

const failed = (code: keyof typeof ERRORS, status: number) =>
  Response.json({ error: { code, message: ERRORS[code] } }, { status });

function stored({ db }: PersonSpace, deviceId: string, edit: Edit) {
  const select = "SELECT id, text, device_id, client_id, edited_at, deleted_at FROM relay_notes";
  return (edit.id !== undefined ? db.prepare(`${select} WHERE id = ?`).bind(edit.id)
    : db.prepare(`${select} WHERE device_id = ? AND client_id = ?`).bind(deviceId, edit.clientId!)).first<Stored>();
}

type File = NonNullable<ReturnType<typeof withTypes>>[number];
type Known = { id: string; transcript: string | null; length_ms: number | null };

/** A listed file the note holds, with its transcript and length as the change gives them, where they differ. */
function retold(file: File, known: Known | undefined): Known | null {
  if (!known) return null;
  const now = { id: file.id, transcript: file.transcript === undefined ? known.transcript : file.transcript,
    length_ms: file.lengthMs ?? known.length_ms };
  return now.transcript !== known.transcript || now.length_ms !== known.length_ms ? now : null;
}

/** The files the change lists that the note lacks, oldest first; the known ones with a new transcript or length; and
 *  the ids of the known files it removes. A file both listed and removed is removed. */
async function fileChanges({ db }: PersonSpace, note: Stored, edit: Edit) {
  const { results } = await db.prepare("SELECT id, transcript, length_ms FROM relay_attachments WHERE note_id = ?").bind(note.id).all<Known>();
  const known = new Map(results.map(file => [file.id, file]));
  const removing = new Set(edit.removed);
  const files = (withTypes(edit.attachments) ?? []).filter(file => !removing.has(file.id));
  return { added: files.filter(file => !known.has(file.id)),
    retold: files.map(file => retold(file, known.get(file.id))).filter(file => file !== null),
    removed: [...removing].filter(id => known.has(id)) };
}

/** Changes the note, or answers why not. Same words, transcripts, and no file new or removed change nothing. */
async function editNote(env: Parameters<typeof wake>[0], space: PersonSpace, deviceId: string, edit: Edit): Promise<Response> {
  const { db } = space;
  const note = await stored(space, deviceId, edit);
  if (!note) return failed("not_found", 404);
  if (note.deleted_at !== null) return failed("deleted", 409);
  const now = Date.now();
  // A phone's clock can run ahead: a change from the future would lock the note against every later one.
  const editedAt = Math.min(edit.editedAt ?? now, now);
  if (note.edited_at !== null && note.edited_at > editedAt) return failed("older", 409);
  const { added, retold, removed } = await fileChanges(space, note, edit);
  const own = note.device_id === deviceId && note.client_id !== null;
  if ((added.length || edit.removed?.length) && !own) return failed("not_own", 400);
  if (note.text === edit.text && !added.length && !retold.length && !removed.length) return Response.json({ id: note.id, updated: false });
  // The sealed files go first, so a step that fails leaves no row without its file.
  if (removed.length) await removeSealed(space, note.id, removed);
  // Logged at the note's own time, as its note.created is, so "Send past data" sends it with the note.
  await db.batch([
    db.prepare("UPDATE relay_notes SET text = ?, edited_at = ? WHERE id = ?").bind(edit.text, editedAt, note.id),
    ...addFiles(db, deviceId, note.client_id!, added),
    ...removed.map(id => db.prepare("DELETE FROM relay_attachments WHERE id = ? AND note_id = ?").bind(id, note.id)),
    ...retold.map(file => db.prepare("UPDATE relay_attachments SET transcript = ?, length_ms = ? WHERE id = ? AND note_id = ?")
      .bind(file.transcript, file.length_ms, file.id, note.id)),
    db.prepare("INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT 'note.updated', id, recorded_at, ? FROM relay_notes WHERE id = ?")
      .bind(now, note.id),
  ]);
  await wake(env, space, ["notes"]);
  return Response.json({ id: note.id, updated: true });
}

export const noteEdit = defineAction({
  operationId: "relay.notes-edit", summary: "Change a note",
  description: "Change the words or a recording's transcript of any note in your space. On a note this device sent, list the files added since, "
    + "and name in `removed` the files to remove. "
    + "The page changes notes as your space's Web device. "
    + "The newer change wins: a change made before the note's last one gets 409. A note in Recently Deleted gets 409 with the code `deleted`. "
    + "Webhooks get it as note.updated.",
  input: editInput, output: z.strictObject({ id: z.string(), updated: z.boolean().describe("False when the words and transcripts were the same and no file was new or removed.") }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asDeviceOrPage<ActionCall>(REFUSAL, async ({ space, deviceId, env, call }) => editNote(env, space, deviceId, call.input as Edit)),
});
