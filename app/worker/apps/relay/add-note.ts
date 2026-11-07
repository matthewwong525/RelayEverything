// Adds one typed note to a person's space, from a phone, an API key or a connected app, then wakes the webhooks that
// take notes. A caller that sends it again with the same id, after losing its answer, gets the same note back.
import type { PersonSpace } from "./space.ts";
import { wake } from "./webhooks/send.ts";

export type TypedNote = { clientId: string; text: string; createdAt: number; lat?: number; lon?: number; accuracy?: number; place?: string };

/** Stores the note once per device and `clientId`: `added` is false when the device sent it before. */
export async function addNote(env: Parameters<typeof wake>[0], space: PersonSpace, deviceId: string, note: TypedNote) {
  const { db } = space;
  const where = note.lat === undefined ? null : "phone";
  const { results } = await db.prepare(`INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, lat, lon, accuracy,
      place, place_from, created_at) VALUES (?, ?, 'typed', ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (device_id, client_id) DO NOTHING RETURNING id`)
    .bind(crypto.randomUUID(), deviceId, note.clientId, note.text, note.createdAt, note.lat ?? null, note.lon ?? null,
      note.accuracy ?? null, note.place ?? null, where, Date.now()).all<{ id: string }>();
  if (results.length) {
    await wake(env, space, ["notes"]);
    return { id: results[0].id, added: true };
  }
  const kept = await db.prepare("SELECT id FROM relay_notes WHERE device_id = ? AND client_id = ?").bind(deviceId, note.clientId).first<{ id: string }>();
  return { id: kept!.id, added: false };
}
