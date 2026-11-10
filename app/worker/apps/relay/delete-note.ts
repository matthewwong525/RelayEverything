// DELETE notes: a phone or the page deletes any note in its space, by the server's `id` or the device's own `clientId`,
// with its files and recording. Phones drop it at their next sync, and webhooks get note.deleted.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asDeviceOrPage } from "./caller.ts";
import { CLIENT_ID } from "./notes.ts";
import type { PersonSpace } from "./space.ts";
import { wake } from "./webhooks/send.ts";

const deleteInput = z.strictObject({
  id: z.string().max(64).optional().describe("The server's id for the note, as GET notes gives it: any note in your space."),
  clientId: z.string().regex(CLIENT_ID).optional().describe("Or the device's own id for a note it sent, as POST notes sent it."),
}).refine(input => (input.id === undefined) !== (input.clientId === undefined), "Give the note's id or its clientId, not both.");
type Delete = z.infer<typeof deleteInput>;

const REFUSAL = "Only a phone key or the Relay Everything page can delete a note.";
const ERRORS = { not_found: "Your space has no note with this id, or this device sent no note with this clientId." };

/** Deletes the note, files first, as POST photos/delete does: a step that fails leaves no row without its file. */
async function deleteNote(env: Parameters<typeof wake>[0], space: PersonSpace, deviceId: string, input: Delete): Promise<Response> {
  const { db, files } = space;
  const select = "SELECT id, audio_key FROM relay_notes";
  const note = await (input.id !== undefined ? db.prepare(`${select} WHERE id = ?`).bind(input.id)
    : db.prepare(`${select} WHERE device_id = ? AND client_id = ?`).bind(deviceId, input.clientId!)).first<{ id: string; audio_key: string | null }>();
  if (!note) return Response.json({ error: { code: "not_found", message: ERRORS.not_found } }, { status: 404 });
  const { results } = await db.prepare("SELECT file_key FROM relay_attachments WHERE note_id = ? AND file_key IS NOT NULL")
    .bind(note.id).all<{ file_key: string }>();
  await files.remove([...results.map(row => row.file_key), ...note.audio_key ? [note.audio_key] : []]);
  // Logged at the note's own time, as its note.created is; the files go with the note by their foreign key.
  await db.batch([
    db.prepare("INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT 'note.deleted', id, recorded_at, ? FROM relay_notes WHERE id = ?")
      .bind(Date.now(), note.id),
    db.prepare("DELETE FROM relay_notes WHERE id = ?").bind(note.id),
  ]);
  await wake(env, space, ["notes"]);
  return Response.json({ id: note.id, deleted: true });
}

export const noteDelete = defineAction({
  operationId: "relay.notes-delete", summary: "Delete a note",
  description: "Delete any note in your space, with its files and recording, from the page, the AI apps and every phone at its next sync. "
    + "Webhooks get it as note.deleted. It can't be undone.",
  input: deleteInput, output: z.strictObject({ id: z.string(), deleted: z.literal(true) }),
  encoding: "query", effect: "write", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asDeviceOrPage<ActionCall>(REFUSAL, async ({ space, deviceId, env, call }) => deleteNote(env, space, deviceId, call.input as Delete)),
});
