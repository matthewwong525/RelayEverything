// A ring note's place: Pebble's webhook carries none, so it takes the stored location point nearest in time, within
// 10 minutes of its recording. A typed note keeps the place its phone sent.
import { MINUTE, type Db } from "./store.ts";

const WINDOW = 10 * MINUTE;
// UPDATE … FROM, not a subquery naming relay_notes: an older SQLite, as on the check runner, can't see the outer row.
const NEAREST = `SELECT n.id AS note, l.lat, l.lon, l.accuracy, l.place,
    row_number() OVER (PARTITION BY n.id ORDER BY abs(l.at - n.recorded_at), l.at) AS rank
  FROM relay_notes n JOIN relay_locations l ON l.at BETWEEN n.recorded_at - ${WINDOW} AND n.recorded_at + ${WINDOW}
  WHERE n.source = 'ring' AND n.lat IS NULL AND n.recorded_at BETWEEN ? AND ?`;

/** Gives every ring note recorded from `from` to `to` that has no place yet the nearest point, and counts them. A
 *  location batch calls it for its own time span, so a note that came before its points still gets one. */
export async function placeRingNotes(db: Db, from: number, to: number): Promise<number> {
  const { results } = await db.prepare(`UPDATE relay_notes SET lat = p.lat, lon = p.lon, accuracy = p.accuracy, place = p.place,
      place_from = 'history' FROM (${NEAREST}) p WHERE p.rank = 1 AND relay_notes.id = p.note
    RETURNING id`).bind(from - WINDOW, to + WINDOW).all();
  return results.length;
}
