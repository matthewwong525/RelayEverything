// Adds one typed note to a person's space, from a phone, an API key or a connected app, then wakes the webhooks that
// take notes. A caller that sends it again with the same id, after losing its answer, gets the same note back.
import type { Db, PersonSpace } from "./space.ts";
import { wake } from "./webhooks/send.ts";

export type TypedNote = { clientId: string; text: string; createdAt: number; lat?: number; lon?: number; accuracy?: number; place?: string;
  attachments?: { id: string; name: string; type: string; size: number }[] };

type NoteFile = NonNullable<TypedNote["attachments"]>[number];

/** The statement that lists files on the device's note by `clientId`, none for no files; a file listed before stays. */
export const addFiles = (db: Db, deviceId: string, clientId: string, files: NoteFile[]) => files.length
  ? [db.prepare(`INSERT INTO relay_attachments (id, note_id, name, content_type, size, created_at)
      SELECT json_extract(f.value, '$.id'), n.id, json_extract(f.value, '$.name'), json_extract(f.value, '$.type'),
        json_extract(f.value, '$.size'), ? FROM json_each(?) f, relay_notes n WHERE n.device_id = ? AND n.client_id = ?
      ON CONFLICT (id) DO NOTHING`).bind(Date.now(), JSON.stringify(files), deviceId, clientId)] : [];

/** Stores the note and its files' names once per device and `clientId`: `added` is false when sent before. */
export async function addNote(env: Parameters<typeof wake>[0], space: PersonSpace, deviceId: string, note: TypedNote) {
  const { db } = space;
  const where = note.lat === undefined ? null : "phone";
  const files = note.attachments ?? [];
  // One transaction: the note, then its files, which name the note by the caller's id. A resend adds neither again.
  const [inserted] = await db.batch([
    db.prepare(`INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, lat, lon, accuracy,
      place, place_from, created_at) VALUES (?, ?, 'typed', ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (device_id, client_id) DO NOTHING RETURNING id`)
      .bind(crypto.randomUUID(), deviceId, note.clientId, note.text, note.createdAt, note.lat ?? null, note.lon ?? null,
        note.accuracy ?? null, note.place ?? null, where, Date.now()),
    ...addFiles(db, deviceId, note.clientId, files),
  ]) as { id: string }[][];
  if (inserted.length) {
    await wake(env, space, ["notes"]);
    return { id: inserted[0].id, added: true };
  }
  const kept = await db.prepare("SELECT id FROM relay_notes WHERE device_id = ? AND client_id = ?").bind(deviceId, note.clientId).first<{ id: string }>();
  return { id: kept!.id, added: false };
}
