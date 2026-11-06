// What Relay Everything's routes share: the shapes a phone sends, refusals, and how many rows one batch may hold.
import { z } from "zod";
import type { Action } from "../../api/contract.ts";
import type { Db } from "./space.ts";

export type Env = Parameters<Action["handler"]>[1];
export type Identity = Parameters<NonNullable<Action["allowed"]>>[0];
export type { Db } from "./space.ts";

export const BATCH = 500;
export const MINUTE = 60_000;

/** A Unix time in milliseconds, from 2001 to 2286, so a time sent in seconds is refused. */
export const time = z.number().int().min(1e12).max(1e13);
export const latitude = z.number().min(-90).max(90);
export const longitude = z.number().min(-180).max(180);
export const accuracy = z.number().min(0).max(100_000);
/** A place's name from the phone's own address lookup, such as a street. */
export const placeName = z.string().min(1).max(200);

const CODES: Record<number, string> = { 400: "invalid_input", 401: "authentication_required", 403: "forbidden", 413: "invalid_input", 503: "unavailable" };

/** A refusal in the shape the shared contract answers with. */
export const refused = (status: 400 | 401 | 403 | 413 | 503, message: string) =>
  Response.json({ error: { code: CODES[status], message } }, { status, headers: { "Cache-Control": "no-store" } });

/** Runs an insert that returns a row for each new row, and counts them. A batch goes in as one bound JSON value, so
 *  500 rows stay one statement under D1's limit on bound values. */
export async function insertNew(db: Db, sql: string, ...values: (string | number)[]): Promise<number> {
  const { results } = await db.prepare(sql).bind(...values).all();
  return results.length;
}
