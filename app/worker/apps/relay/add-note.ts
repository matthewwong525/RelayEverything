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

/** The statement that keeps a new note's place as one location point of its device at the note's time, none for no
 *  place. It runs before the note's insert, so a resent note adds no second point; a point already there stays. */
const addPoint = (db: Db, deviceId: string, note: TypedNote) => note.lat === undefined || note.lon === undefined ? [] : [
  db.prepare(`INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, place, created_at) SELECT ?, ?, ?, ?, ?, ?, ?
    WHERE NOT EXISTS (SELECT 1 FROM relay_notes WHERE device_id = ? AND client_id = ?) ON CONFLICT (device_id, at) DO NOTHING RETURNING id`)
    .bind(deviceId, note.createdAt, note.lat, note.lon, note.accuracy ?? 0, note.place ?? null, Date.now(), deviceId, note.clientId)];

/** Stores the note, with no place, and its files' names once per device and `clientId`: `added` is false when sent
 *  before. A place sent with it becomes one location point. */
export async function addNote(env: Parameters<typeof wake>[0], space: PersonSpace, deviceId: string, note: TypedNote) {
  const { db } = space;
  const files = note.attachments ?? [];
  const point = addPoint(db, deviceId, note);
  // One transaction: the point, the note, then its files, named by the caller's id. A resend adds none of them again.
  const results = await db.batch([
    ...point,
    db.prepare(`INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at)
      VALUES (?, ?, 'typed', ?, ?, ?, ?) ON CONFLICT (device_id, client_id) DO NOTHING RETURNING id`)
      .bind(crypto.randomUUID(), deviceId, note.clientId, note.text, note.createdAt, Date.now()),
    ...addFiles(db, deviceId, note.clientId, files),
  ]) as { id: string }[][];
  const inserted = results[point.length];
  if (inserted.length) {
    await wake(env, space, point.length && results[0].length ? ["notes", "locations"] : ["notes"]);
    return { id: inserted[0].id, added: true };
  }
  const kept = await db.prepare("SELECT id FROM relay_notes WHERE device_id = ? AND client_id = ?").bind(deviceId, note.clientId).first<{ id: string }>();
  return { id: kept!.id, added: false };
}
