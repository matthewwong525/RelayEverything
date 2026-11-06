// POST /apps/relay/move: the one-time move of the owner's old data from D1 into their own space, a page at a time.
// scripts/relay-move-to-space.mjs calls it with a ticket it wrote to the directory. wiki/relay-spaces.md
import { z } from "zod";
import { directory, hashToken, joinPerson, type DirectoryEnv } from "./people.ts";
import { MOVED, spaceOf, vouch, type PersonSpace, type Row, type SpaceEnv } from "./space.ts";
import { refused } from "./store.ts";

export type MoveEnv = DirectoryEnv & SpaceEnv;

const PAGE = 200;
const input = z.union([
  z.strictObject({ table: z.enum(MOVED), after: z.number().int().min(0) }),
  z.strictObject({ counts: z.literal(true) }),
]);

/** True when the request carries an unexpired ticket from the directory. */
async function ticketed(request: Request, env: MoveEnv): Promise<boolean> {
  const ticket = /^Bearer (\S{20,200})$/.exec(request.headers.get("Authorization") ?? "")?.[1];
  if (!ticket) return false;
  return !!await directory(env).prepare("SELECT 1 AS ok FROM relay_move_tickets WHERE token_sha256 = ? AND expires_at > ?")
    .bind(await hashToken(ticket), Date.now()).first();
}

/** The ids in `rows` that the space has already: a second run neither seals a recording again nor resets a webhook. */
async function kept(space: PersonSpace, table: "relay_notes" | "relay_webhooks", rows: Row[]): Promise<Set<unknown>> {
  const { results } = await space.db.prepare(`SELECT id FROM ${table} WHERE id IN (SELECT value FROM json_each(?))`)
    .bind(JSON.stringify(rows.map(row => row.id))).all<{ id: string }>();
  return new Set(results.map(row => row.id));
}

/** Seals each new note's recording into the person's folder; a recording that is gone leaves its note without one. */
async function adoptRecordings(space: PersonSpace, rows: Row[]): Promise<number> {
  const have = await kept(space, "relay_notes", rows);
  let missing = 0;
  for (const row of rows.filter(row => row.audio_key !== null && !have.has(row.id))) {
    row.audio_key = await space.files.adopt(String(row.audio_key), String(row.id));
    if (row.audio_key === null) missing++;
  }
  return missing;
}

/** A moved webhook starts at the end of the space's send log: the moved notes were sent already, from the old one. */
async function startAtEnd(space: PersonSpace, rows: Row[]) {
  const end = await space.db.prepare("SELECT coalesce(max(seq), 0) AS seq FROM relay_outbox").first<{ seq: number }>();
  for (const row of rows) Object.assign(row, { sent_seq: end!.seq, pending_seq: null, backfill_seq: null, lease_until: null });
}

async function movePage(env: MoveEnv, space: PersonSpace, table: typeof MOVED[number], after: number) {
  const { results } = await directory(env).prepare(`SELECT rowid AS _rowid, * FROM ${table} WHERE rowid > ? ORDER BY rowid LIMIT ${PAGE}`)
    .bind(after).all<Row & { _rowid: number }>();
  const rows: Row[] = results.map(({ _rowid, ...row }) => row);
  const missingFiles = table === "relay_notes" ? await adoptRecordings(space, rows) : 0;
  if (table === "relay_webhooks") await startAtEnd(space, rows);
  const added = rows.length ? await space.import(table, rows) : 0;
  if (table === "relay_webhooks" && rows.length) await space.watch();
  return { table, read: rows.length, added, next: results.length === PAGE ? results.at(-1)!._rowid : null, missingFiles };
}

async function oldCounts(env: MoveEnv) {
  const counts = await Promise.all(MOVED.map(table =>
    directory(env).prepare(`SELECT count(*) AS count FROM ${table}`).first<{ count: number }>()));
  return Object.fromEntries(MOVED.map((table, index) => [table, counts[index]!.count]));
}

export async function move(request: Request, env: MoveEnv): Promise<Response> {
  if (!await ticketed(request, env)) return refused(403, "This move ticket is wrong or has expired.");
  const person = env.WONG_OWNER_EMAIL ? await joinPerson(env, env.WONG_OWNER_EMAIL) : null;
  if (!person) return Response.json({ error: { code: "conflict", message: "No owner email is set." } }, { status: 409 });
  const body = input.safeParse(await request.json().catch(() => null));
  if (!body.success) return refused(400, "Send a table to move and where to start, or counts: true.");
  const space = spaceOf(env, vouch("move", person.id, { email: person.email }));
  if ("counts" in body.data) return Response.json({ old: await oldCounts(env), space: await space.counts() });
  return Response.json(await movePage(env, space, body.data.table, body.data.after));
}
