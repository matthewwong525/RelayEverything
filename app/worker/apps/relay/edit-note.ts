// PATCH notes: new words for any note in the phone's space, by the server's `id` or by the phone's own `clientId`, and
// files added since to a note it sent. Logs one note.updated; a change older than the note's last one changes nothing.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { addFiles } from "./add-note.ts";
import { asDevice } from "./caller.ts";
import { CLIENT_ID, hasWords, noteFiles, noteText, withTypes } from "./notes.ts";
import type { PersonSpace } from "./space.ts";
import { refused, time } from "./store.ts";
import { wake } from "./webhooks/send.ts";

const editInput = z.strictObject({
  id: z.string().max(64).optional().describe("The server's id for the note, as GET notes gives it: any note in your space."),
  clientId: z.string().regex(CLIENT_ID).optional().describe("Or the phone's own id for a note it sent, as POST notes sent it."),
  text: noteText.describe("What the note says now, in place of its words before. It can be empty only when the note has files."),
  attachments: noteFiles.optional()
    .describe("All of the note's files now, up to 10. A file the server lacks is added: send its bytes after, with POST attachments."),
  editedAt: time.optional().describe("When the phone made the change, in Unix ms; now when left out. A later time is taken as now."),
}).refine(edit => (edit.id === undefined) !== (edit.clientId === undefined), "Give the note's id or its clientId, not both.")
  .refine(hasWords, "Give the note words or a file.");
type Edit = z.infer<typeof editInput>;
type Stored = { id: string; text: string; device_id: string; client_id: string | null; edited_at: number | null };

const REFUSAL = "Only a Relay Everything phone key can change a note.";
const ERRORS = { not_found: "Your space has no note with this id, or this device sent no note with this clientId.",
  older: "The note changed after this change was made, so the newer words stay: GET notes gives them.",
  not_own: "Add a file only to a note this phone sent." };

const failed = (code: keyof typeof ERRORS, status: number) => Response.json({ error: { code, message: ERRORS[code] } }, { status });

function stored({ db }: PersonSpace, deviceId: string, edit: Edit) {
  const select = "SELECT id, text, device_id, client_id, edited_at FROM relay_notes";
  return (edit.id !== undefined ? db.prepare(`${select} WHERE id = ?`).bind(edit.id)
    : db.prepare(`${select} WHERE device_id = ? AND client_id = ?`).bind(deviceId, edit.clientId!)).first<Stored>();
}

/** The files the change lists that the note lacks, oldest first. */
async function addedFiles({ db }: PersonSpace, note: Stored, edit: Edit) {
  const { results } = await db.prepare("SELECT id FROM relay_attachments WHERE note_id = ?").bind(note.id).all<{ id: string }>();
  const known = new Set(results.map(file => file.id));
  return withTypes(edit.attachments)?.filter(file => !known.has(file.id)) ?? [];
}

/** Changes the note, or answers why not. Same words and no new file change nothing. */
async function editNote(env: Parameters<typeof wake>[0], space: PersonSpace, deviceId: string, edit: Edit): Promise<Response> {
  const { db } = space;
  const note = await stored(space, deviceId, edit);
  if (!note) return failed("not_found", 404);
  const now = Date.now();
  // A phone's clock can run ahead: a change from the future would lock the note against every later one.
  const editedAt = Math.min(edit.editedAt ?? now, now);
  if (note.edited_at !== null && note.edited_at > editedAt) return failed("older", 409);
  const added = await addedFiles(space, note, edit);
  if (added.length && (note.device_id !== deviceId || note.client_id === null)) return failed("not_own", 400);
  if (note.text === edit.text && !added.length) return Response.json({ id: note.id, updated: false });
  // Logged at the note's own time, as its note.created is, so "Send past data" sends it with the note.
  await db.batch([
    db.prepare("UPDATE relay_notes SET text = ?, edited_at = ? WHERE id = ?").bind(edit.text, editedAt, note.id),
    ...addFiles(db, deviceId, note.client_id!, added),
    db.prepare("INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT 'note.updated', id, recorded_at, ? FROM relay_notes WHERE id = ?")
      .bind(now, note.id),
  ]);
  await wake(env, space, ["notes"]);
  return Response.json({ id: note.id, updated: true });
}

export const noteEdit = defineAction({
  operationId: "relay.notes-edit", summary: "Change a note",
  description: "Change the words of any note in your space, and list the files added since to a note this phone sent. "
    + "The newer change wins: a change made before the note's last one gets 409. Webhooks get it as note.updated.",
  input: editInput, output: z.strictObject({ id: z.string(), updated: z.boolean().describe("False when the words were the same and no file was new.") }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asDevice<ActionCall>(REFUSAL, async ({ space, device, env, call }) => {
    if (device.reaches !== "phone") return refused(403, REFUSAL);
    return editNote(env, space, device.id, call.input as Edit);
  }),
});
