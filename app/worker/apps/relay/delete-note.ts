// DELETE notes: a phone or the page moves any note in its space to Recently Deleted, by the server's `id` or the
// device's own `clientId`; `forever` deletes it with its files and recording. POST notes/recover moves it back.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asDeviceOrPage } from "./caller.ts";
import { CLIENT_ID } from "./notes.ts";
import { removeForever } from "./recently-deleted.ts";
import type { PersonSpace } from "./space.ts";
import { time } from "./store.ts";
import { wake } from "./webhooks/send.ts";

const named = {
  id: z.string().max(64).optional().describe("The server's id for the note, as GET notes gives it: any note in your space."),
  clientId: z.string().regex(CLIENT_ID).optional().describe("Or the device's own id for a note it sent, as POST notes sent it."),
};
const oneName = (input: { id?: string; clientId?: string }) => (input.id === undefined) !== (input.clientId === undefined);
const ONE_NAME = "Give the note's id or its clientId, not both.";
const deleteInput = z.strictObject({ ...named,
  forever: z.boolean().optional().describe("True to delete the note for good now, with its files and recording; it can't be undone. "
    + "Left out, the note moves to Recently Deleted for 30 days."),
}).refine(oneName, ONE_NAME);
const recoverInput = z.strictObject(named).refine(oneName, ONE_NAME);
type Named = z.infer<typeof recoverInput>;
type Delete = z.infer<typeof deleteInput>;
type Stored = { id: string; audio_key: string | null; deleted_at: number | null };
type Call = { env: Parameters<typeof wake>[0]; space: PersonSpace; deviceId: string };

const ERRORS = { not_found: "Your space has no note with this id, or this device sent no note with this clientId." };
const notFound = () => Response.json({ error: { code: "not_found", message: ERRORS.not_found } }, { status: 404 });

function stored({ db }: PersonSpace, deviceId: string, input: Named) {
  const select = "SELECT id, audio_key, deleted_at FROM relay_notes";
  return (input.id !== undefined ? db.prepare(`${select} WHERE id = ?`).bind(input.id)
    : db.prepare(`${select} WHERE device_id = ? AND client_id = ?`).bind(deviceId, input.clientId!)).first<Stored>();
}

/** Logs a note's message at its own time, as its note.created is, so "Send past data" sends it with the note. */
const logged = ({ db }: PersonSpace, kind: string, id: string, at: number) =>
  db.prepare("INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT ?, id, recorded_at, ? FROM relay_notes WHERE id = ?").bind(kind, at, id);

/** Moves the note to Recently Deleted, once: a second move keeps the first time. Sets the space's alarm for its end. */
async function deleteNote({ env, space, deviceId }: Call, input: Delete): Promise<Response> {
  const note = await stored(space, deviceId, input);
  if (!note) return notFound();
  if (input.forever) {
    if (await removeForever(space, note)) await wake(env, space, ["notes"]);
    return Response.json({ id: note.id, deleted: true });
  }
  if (note.deleted_at !== null) return Response.json({ id: note.id, deleted: true, deletedAt: note.deleted_at });
  const at = Date.now();
  await space.db.batch([space.db.prepare("UPDATE relay_notes SET deleted_at = ? WHERE id = ?").bind(at, note.id),
    logged(space, "note.deleted", note.id, at)]);
  await space.watchDeleted();
  await wake(env, space, ["notes"]);
  return Response.json({ id: note.id, deleted: true, deletedAt: at });
}

/** Moves the note back from Recently Deleted; logs it whole, then each stored file, for a webhook that dropped it. */
async function recoverNote({ env, space, deviceId }: Call, input: Named): Promise<Response> {
  const note = await stored(space, deviceId, input);
  if (!note) return notFound();
  if (note.deleted_at === null) return Response.json({ id: note.id, recovered: true });
  const { db } = space;
  const at = Date.now();
  await db.batch([db.prepare("UPDATE relay_notes SET deleted_at = NULL WHERE id = ?").bind(note.id), logged(space, "note.recovered", note.id, at),
    db.prepare(`INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT 'note.file', a.id, n.recorded_at, ? FROM relay_attachments a
      JOIN relay_notes n ON n.id = a.note_id WHERE a.note_id = ? AND a.file_key IS NOT NULL ORDER BY a.rowid`).bind(at, note.id)]);
  await wake(env, space, ["notes"]);
  return Response.json({ id: note.id, recovered: true });
}

export const noteDelete = defineAction({
  operationId: "relay.notes-delete", summary: "Delete a note",
  description: "Move any note in your space to Recently Deleted for 30 days: the page and every phone show it there after their next sync, "
    + "and the AI apps no longer find it. After 30 days, or with `forever`, it goes for good with its files and recording. "
    + "Webhooks get note.deleted once: at the move, or at a delete for good of a note not in Recently Deleted.",
  input: deleteInput, output: z.strictObject({ id: z.string(), deleted: z.literal(true),
    deletedAt: time.optional().describe("When the note moved to Recently Deleted, in Unix ms; left out after a delete for good.") }),
  encoding: "query", effect: "write", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asDeviceOrPage<ActionCall>("Only a phone key or the Relay Everything page can delete a note.",
    async ({ space, deviceId, env, call }) => deleteNote({ env, space, deviceId }, call.input as Delete)),
});

export const noteRecover = defineAction({
  operationId: "relay.notes-recover", summary: "Recover a deleted note",
  description: "Move a note in Recently Deleted back to your notes, as it was, on the page and every phone at its next sync. "
    + "A note not in Recently Deleted stays as it is. Webhooks get it as note.recovered, with the whole note.",
  input: recoverInput, output: z.strictObject({ id: z.string(), recovered: z.literal(true) }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asDeviceOrPage<ActionCall>("Only a phone key or the Relay Everything page can recover a note.",
    async ({ space, deviceId, env, call }) => recoverNote({ env, space, deviceId }, call.input as Named)),
});
