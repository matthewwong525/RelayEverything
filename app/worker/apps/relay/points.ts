// The location points behind a stay, a trip or a time, for the AI connector's points read: SELECT only, as in
// queries.ts, and thinned in SQL so a long trip stays one short answer.
import { going, type StayRow } from "./queries.ts";
import type { Db } from "./store.ts";

/** At most this many points in one answer: more are kept one per equal step, with the first and the last. */
export const MAX_POINTS = 500;
type PointRow = { at: number; lat: number; lon: number; accuracy: number; place: string | null; total: number };

/** The points `where` picks, oldest first, thinned in SQL so at most MAX_POINTS leave the space, and their count. */
async function thinnedPoints(db: Db, where: string, values: (number | string)[]) {
  // Integer division keeps the first row of each of MAX_POINTS - 1 equal steps; the first and the last row always pass.
  const { results } = await db.prepare(`WITH p AS (SELECT at, lat, lon, accuracy, place, ROW_NUMBER() OVER (ORDER BY at, id) AS n,
      COUNT(*) OVER () AS total FROM relay_locations WHERE ${where})
    SELECT at, lat, lon, accuracy, place, total FROM p WHERE total <= ${MAX_POINTS} OR n = 1
      OR (n - 1) * ${MAX_POINTS - 1} / (total - 1) > (n - 2) * ${MAX_POINTS - 1} / (total - 1) ORDER BY n`)
    .bind(...values).all<PointRow>();
  return { total: results[0]?.total ?? 0,
    points: results.map(({ at, lat, lon, accuracy, place }) => ({ at, lat, lon, accuracy, ...place !== null && { place } })) };
}

/** One stay's or trip's points, from its own phone only; one still going reads to now. Null for no such id. */
export async function stayPoints(db: Db, id: number) {
  const row = await db.prepare("SELECT device_id, kind, start_at, end_at, ongoing, updated_at FROM relay_stays WHERE id = ?")
    .bind(id).first<Pick<StayRow, "kind" | "start_at" | "end_at" | "ongoing" | "updated_at"> & { device_id: string }>();
  if (!row) return null;
  const end = going(row) ? Math.max(Date.now(), row.end_at) : row.end_at;
  const found = await thinnedPoints(db, "device_id = ? AND at >= ? AND at <= ?", [row.device_id, row.start_at, end]);
  return { kind: row.kind, start: row.start_at, end, ...found };
}

/** Every phone's points from `from` to before `to`. */
export const rangePoints = (db: Db, from: number, to: number) => thinnedPoints(db, "at >= ? AND at < ?", [from, to]);
