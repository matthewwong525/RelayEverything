// Recently Deleted: a deleted note waits 30 days with `deleted_at` set, then goes for good with its files and
// recording. The space's alarm queues the purge, and GET notes runs it too. openspec/changes/recently-deleted
import type { PersonSpace } from "./space.ts";
import { MINUTE } from "./store.ts";

/** How long a deleted note waits in Recently Deleted. */
export const KEEP_DELETED = 30 * 24 * 60 * MINUTE;
/** When the first deleted note's 30 days end, as `at`, or null with none waiting. */
export const FIRST_END = `SELECT min(deleted_at) + ${KEEP_DELETED} AS at FROM relay_notes WHERE deleted_at IS NOT NULL`;

type Stored = { id: string; audio_key: string | null; deleted_at: number | null };

/** Deletes the note for good, files first, so a step that fails leaves no row without its file. A note not yet in
 *  Recently Deleted logs one note.deleted; one there already sent it. Says whether it logged. */
export async function removeForever({ db, files }: Pick<PersonSpace, "db" | "files">, note: Stored): Promise<boolean> {
  const { results } = await db.prepare("SELECT file_key FROM relay_attachments WHERE note_id = ? AND file_key IS NOT NULL")
    .bind(note.id).all<{ file_key: string }>();
  await files.remove([...results.map(row => row.file_key), ...note.audio_key ? [note.audio_key] : []]);
  const logged = note.deleted_at === null;
  // Logged at the note's own time, as its note.created is; the files go with the note by their foreign key.
  await db.batch([
    ...logged ? [db.prepare("INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT 'note.deleted', id, recorded_at, ? FROM relay_notes WHERE id = ?")
      .bind(Date.now(), note.id)] : [],
    db.prepare("DELETE FROM relay_notes WHERE id = ?").bind(note.id),
  ]);
  return logged;
}

/** Deletes for good each note 30 days in Recently Deleted; answers how many. */
export async function purgeDue(space: Pick<PersonSpace, "db" | "files">): Promise<number> {
  const { results } = await space.db.prepare("SELECT id, audio_key, deleted_at FROM relay_notes WHERE deleted_at <= ? ORDER BY deleted_at")
    .bind(Date.now() - KEEP_DELETED).all<Stored>();
  for (const note of results) await removeForever(space, note);
  return results.length;
}
