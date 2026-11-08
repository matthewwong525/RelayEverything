// PATCH notes: new words for a note its own phone sent before, and any files added since. Logs one note.updated, after
// the note's note.created; each new file's bytes come after, by POST attachments. Another device's note is not found.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { addFiles } from "./add-note.ts";
import { asDevice } from "./caller.ts";
import { CLIENT_ID, hasWords, noteFiles, noteText, withTypes } from "./notes.ts";
import type { PersonSpace } from "./space.ts";
import { refused } from "./store.ts";
import { wake } from "./webhooks/send.ts";

const editInput = z.strictObject({
  clientId: z.string().regex(CLIENT_ID).describe("The phone's own id for the note, as POST notes sent it."),
  text: noteText.describe("What the note says now, in place of its words before. It can be empty only when the note has files."),
  attachments: noteFiles.optional()
    .describe("All of the note's files now, up to 10. A file the server lacks is added: send its bytes after, with POST attachments."),
}).refine(hasWords, "Give the note words or a file.");
type Edit = z.infer<typeof editInput>;

const REFUSAL = "Only the Relay Everything phone key that sent a note can change it.";
const ERRORS = { not_found: "This device sent no note with this clientId." };

/** Changes the device's note, or null when it has none by `clientId`. Same words and no new file change nothing. */
async function editNote(env: Parameters<typeof wake>[0], space: PersonSpace, deviceId: string, edit: Edit) {
  const { db } = space;
  const note = await db.prepare("SELECT id, text FROM relay_notes WHERE device_id = ? AND client_id = ?").bind(deviceId, edit.clientId)
    .first<{ id: string; text: string }>();
  if (!note) return null;
  const { results } = await db.prepare("SELECT id FROM relay_attachments WHERE note_id = ?").bind(note.id).all<{ id: string }>();
  const known = new Set(results.map(file => file.id));
  const added = withTypes(edit.attachments)?.filter(file => !known.has(file.id)) ?? [];
  if (note.text === edit.text && !added.length) return { id: note.id, updated: false };
  const now = Date.now();
  // Logged at the note's own time, as its note.created is, so "Send past data" sends it with the note.
  await db.batch([
    db.prepare("UPDATE relay_notes SET text = ?, edited_at = ? WHERE id = ?").bind(edit.text, now, note.id),
    ...addFiles(db, deviceId, edit.clientId, added),
    db.prepare("INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT 'note.updated', id, recorded_at, ? FROM relay_notes WHERE id = ?")
      .bind(now, note.id),
  ]);
  await wake(env, space, ["notes"]);
  return { id: note.id, updated: true };
}

export const noteEdit = defineAction({
  operationId: "relay.notes-edit", summary: "Change a typed note",
  description: "Change the words of a note this phone sent before, and list the files added since. Webhooks get it as note.updated.",
  input: editInput, output: z.strictObject({ id: z.string(), updated: z.boolean().describe("False when the words were the same and no file was new.") }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asDevice<ActionCall>(REFUSAL, async ({ space, device, env, call }) => {
    if (device.reaches !== "phone") return refused(403, REFUSAL);
    const changed = await editNote(env, space, device.id, call.input as Edit);
    return changed ? Response.json(changed) : Response.json({ error: { code: "not_found", message: ERRORS.not_found } }, { status: 404 });
  }),
});
