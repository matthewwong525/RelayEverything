import { afterEach, expect, it, vi } from "vitest";
import { ANA, benPhone, bucket, call, db, env, ipad, laptop, matthew, NOW, phone, queue, rows, spaces } from "../../../tests/relay";
import { relayStore } from "../../relay-memory/store";
import { changeTags } from "./memory.ts";
import { daySummary, noteById, notePage } from "./queries.ts";
import { KEEP_DELETED } from "./recently-deleted.ts";
import { spaceOf, vouch } from "./space.ts";
import { consume } from "./webhooks/send.ts";

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;
const SWEEP = 15 * MINUTE;
const files = { file: `people/${ANA}/attachments/f-mail`, audio: `people/${ANA}/n-mail`, other: `people/${ANA}/attachments/f-other` };
afterEach(() => { vi.unstubAllGlobals(); });

/** Two emailed notes in Ana's space, each with a stored file, the first with a recording. */
function emailed() {
  db.sql.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches)
      VALUES ('d-mail', 'Email', 'inbox:email', '', ${NOW}, 'inbox');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, audio_key, recorded_at, created_at)
      VALUES ('n-mail', 'd-mail', 'typed', 'email:m-1', 'Flight to Lisbon', '${files.audio}', ${NOW - 60 * MINUTE}, ${NOW - 60 * MINUTE}),
        ('n-other', 'd-mail', 'typed', 'email:m-2', 'Hotel', NULL, ${NOW - 30 * MINUTE}, ${NOW - 30 * MINUTE});
    INSERT INTO relay_attachments (id, note_id, name, content_type, size, file_key, created_at)
      VALUES ('f-mail', 'n-mail', 'ticket.pdf', 'application/pdf', 3, '${files.file}', ${NOW}),
        ('f-other', 'n-other', 'hotel.pdf', 'application/pdf', 3, '${files.other}', ${NOW});`);
  for (const key of Object.values(files)) bucket.objects.set(key, new Uint8Array([1, 2, 3]));
}
const move = (id: string) => call(phone, "DELETE", "notes", { id });
const recover = (input: Record<string, string>, who = phone) => call(who, "POST", "notes/recover", input);
const log = () => rows("relay_outbox").map(row => [row.kind, row.ref]);
const feed = async (who = phone, query: Record<string, string> = { trash: "1" }) =>
  (await call(who, "GET", "notes", { since: "0", deleted: "1", ...query })).json.notes as unknown as Record<string, unknown>[];
/** Runs each message waiting in the queue, as the app's consumer does. */
async function drain() {
  const messages = queue.sent.splice(0).map(body => ({ body, ack: vi.fn(), retry: vi.fn() }));
  await consume({ queue: "relay-everything-webhooks", messages } as unknown as MessageBatch, env());
}

it("moves a note to Recently Deleted, keeps it and its files, and keeps the first time on a second move", async () => {
  emailed();
  expect(await move("n-mail")).toEqual({ status: 200, json: { id: "n-mail", deleted: true, deletedAt: NOW } });
  expect(rows("relay_notes").map(row => [row.id, row.deleted_at])).toEqual([["n-mail", NOW], ["n-other", null]]);
  expect(rows("relay_attachments")).toHaveLength(2);
  expect(bucket.objects.size).toBe(3);
  vi.setSystemTime(NOW + MINUTE);
  expect((await call(ipad, "DELETE", "notes", { id: "n-mail" })).json).toEqual({ id: "n-mail", deleted: true, deletedAt: NOW });
  expect(log().filter(([kind]) => kind === "note.deleted")).toEqual([["note.deleted", "n-mail"]]);
  // A note in Recently Deleted can't be changed until it comes back.
  expect(await call(ipad, "PATCH", "notes", { id: "n-mail", text: "Flight" }))
    .toMatchObject({ status: 409, json: { error: { code: "deleted" } } });
  expect(rows("relay_notes")[0].text).toBe("Flight to Lisbon");
});

it("recovers a moved note by id or by the phone's own clientId, and a note not deleted stays as it is", async () => {
  emailed();
  await move("n-mail");
  expect(await recover({ id: "n-mail" })).toEqual({ status: 200, json: { id: "n-mail", recovered: true } });
  expect(rows("relay_notes").map(row => row.deleted_at)).toEqual([null, null]);
  expect(log().slice(-3)).toEqual([["note.deleted", "n-mail"], ["note.recovered", "n-mail"], ["note.file", "f-mail"]]);
  expect(await recover({ id: "n-mail" })).toEqual({ status: 200, json: { id: "n-mail", recovered: true } });
  expect(log().filter(([kind]) => kind === "note.recovered")).toHaveLength(1);
  expect((await call(ipad, "PATCH", "notes", { id: "n-mail", text: "Flight" })).status).toBe(200);
  const { json } = await call(phone, "POST", "notes", { clientId: "note-recover-01", text: "Buy milk", createdAt: NOW - MINUTE });
  await call(phone, "DELETE", "notes", { clientId: "note-recover-01" });
  expect((await recover({ clientId: "note-recover-01" }, ipad)).status).toBe(404);
  expect(await recover({ clientId: "note-recover-01" })).toEqual({ status: 200, json: { id: json.id, recovered: true } });
  expect((await recover({ id: "n-mail", clientId: "email:m-1" })).status).toBe(400);
});

it("deletes for good with forever, moved or not, and then finds no note to recover, change or delete", async () => {
  emailed();
  await move("n-mail");
  expect(await call(phone, "DELETE", "notes", { id: "n-mail", forever: "true" })).toEqual({ status: 200, json: { id: "n-mail", deleted: true } });
  expect(rows("relay_notes").map(row => row.id)).toEqual(["n-other"]);
  expect([...bucket.objects.keys()]).toEqual([files.other]);
  // It sent note.deleted at the move, and sends nothing more.
  expect(log().filter(([kind]) => kind === "note.deleted")).toHaveLength(1);
  expect(await recover({ id: "n-mail" })).toMatchObject({ status: 404, json: { error: { code: "not_found" } } });
  expect((await call(ipad, "PATCH", "notes", { id: "n-mail", text: "Flight" })).status).toBe(404);
  expect((await move("n-mail")).status).toBe(404);
  expect((await call(phone, "DELETE", "notes", { id: "n-other", forever: "1" })).status).toBe(400);
});

it("lets only a phone key or the page recover a note, and only in its own space", async () => {
  emailed();
  await move("n-mail");
  expect((await recover({ id: "n-mail" }, benPhone)).status).toBe(404);
  expect((await recover({ id: "n-mail" }, laptop)).status).toBe(403);
  expect((await recover({ id: "n-mail" }, null)).status).toBe(401);
  expect(rows("relay_notes")[0].deleted_at).toBe(NOW);
  expect((await recover({ id: "n-mail" }, matthew)).json).toEqual({ id: "n-mail", recovered: true });
});

it("gives a moved note in the feed with its time, and leaves it out of the timeline, the AI apps and memory", async () => {
  emailed();
  await move("n-mail");
  expect((await feed()).map(note => [note.id, note.deletedAt])).toEqual([["n-other", null], ["n-mail", NOW]]);
  expect((await call(matthew, "GET", "timeline")).json.notes.map(note => note.id)).toEqual(["n-other"]);
  expect((await call(matthew, "GET", "summary", { day: "2026-11-05" })).json).toMatchObject({ notes: 1 });
  const space = spaceOf(env() as never, vouch("grant", ANA));
  expect((await notePage(space.db, { words: ["Lisbon"], limit: 10 })).notes).toEqual([]);
  expect((await notePage(space.db, { limit: 10 })).notes.map(note => note.id)).toEqual(["n-other"]);
  expect(await noteById(space.db, "n-mail")).toBeNull();
  expect((await daySummary(space.db, NOW - DAY, NOW + DAY)).notes).toBe(1);
  expect(await changeTags(space.db, "d-phone", "note", "n-mail", { add: ["trip"] })).toBeNull();
  const store = relayStore(space, { role: "admin", subject: ANA, email: "ana@example.com" }, "d-laptop");
  const fact = (link: string) => store.write({ source: "save", slug: "demo", facts: [{ type: "project", body: "A trip.", sources: [link] } as never] });
  await expect(fact("relay:note/n-mail")).rejects.toMatchObject({ kind: "query" });
  expect((await fact("relay:note/n-other")).ids).toHaveLength(1);
  // Back from Recently Deleted, the AI apps find it again.
  await recover({ id: "n-mail" });
  expect(await noteById(space.db, "n-mail")).toMatchObject({ id: "n-mail" });
});

it("gives an app build from before Recently Deleted a moved note as deleted, or leaves it out, and a recovered one whole", async () => {
  emailed();
  await move("n-mail");
  expect(await feed(phone, {})).toEqual([expect.objectContaining({ id: "n-other", deletedAt: null }),
    { id: "n-mail", clientId: "email:m-1", deleted: true }]);
  const older = (await call(phone, "GET", "notes", { since: "0" })).json;
  expect([older.notes.map(note => note.id), older.more]).toEqual([["n-other"], false]);
  expect(older.next).toBe((await call(phone, "GET", "notes", { since: "0", trash: "1" })).json.next);
  await recover({ id: "n-mail" });
  expect((await feed(phone, {})).map(note => [note.id, note.deleted ?? false])).toEqual([["n-other", false], ["n-mail", false]]);
});

it("sets the space's alarm for the end of 30 days, and deletes the note for good then, with its files", async () => {
  emailed();
  await move("n-mail");
  expect(spaces.alarmOf(ANA)).toBe(NOW + KEEP_DELETED);
  vi.setSystemTime(NOW + DAY);
  await move("n-other");
  expect(spaces.alarmOf(ANA)).toBe(NOW + KEEP_DELETED);
  // A day early, the alarm queues nothing.
  vi.setSystemTime(NOW + KEEP_DELETED - MINUTE);
  await spaces.alarm(ANA);
  expect(queue.sent.filter(body => (body as { purge?: boolean }).purge)).toEqual([]);
  queue.sent = [];
  vi.setSystemTime(NOW + KEEP_DELETED);
  await spaces.alarm(ANA);
  expect(queue.sent).toEqual([{ purge: true, person: ANA }]);
  expect(spaces.alarmOf(ANA)).toBe(NOW + KEEP_DELETED + SWEEP);
  await drain();
  expect(rows("relay_notes").map(row => row.id)).toEqual(["n-other"]);
  expect(rows("relay_attachments").map(row => row.id)).toEqual(["f-other"]);
  expect([...bucket.objects.keys()]).toEqual([files.other]);
  expect(log().filter(([kind]) => kind === "note.deleted")).toHaveLength(2);
  // The next alarm waits for the second note's 30 days, then none is left to wait for.
  vi.setSystemTime(NOW + KEEP_DELETED + SWEEP);
  await spaces.alarm(ANA);
  expect(spaces.alarmOf(ANA)).toBe(NOW + DAY + KEEP_DELETED);
});

it("keeps a new webhook's 15-minute sweep after a delete set the alarm 30 days out, and still deletes the note at 30 days", async () => {
  emailed();
  await move("n-mail");
  expect(spaces.alarmOf(ANA)).toBe(NOW + KEEP_DELETED);
  expect((await call(matthew, "POST", "webhooks", { name: "Database", url: "https://db.example.com/relay", kinds: [] })).status).toBe(200);
  expect(spaces.alarmOf(ANA)).toBe(NOW + SWEEP);
  // A second move keeps the sooner sweep.
  await move("n-other");
  expect(spaces.alarmOf(ANA)).toBe(NOW + SWEEP);
  vi.setSystemTime(NOW + SWEEP);
  await spaces.alarm(ANA);
  expect(spaces.alarmOf(ANA)).toBe(NOW + 2 * SWEEP);
  queue.sent = [];
  vi.setSystemTime(NOW + KEEP_DELETED);
  await spaces.alarm(ANA);
  expect(queue.sent).toContainEqual({ purge: true, person: ANA });
  expect(spaces.alarmOf(ANA)).toBe(NOW + KEEP_DELETED + SWEEP);
});

it("deletes each note 30 days in Recently Deleted for good when a phone syncs, and gives it as deleted", async () => {
  emailed();
  await move("n-mail");
  vi.setSystemTime(NOW + KEEP_DELETED - MINUTE);
  expect(await feed()).toHaveLength(2);
  vi.setSystemTime(NOW + KEEP_DELETED);
  expect((await feed()).map(note => [note.id, note.deleted ?? false])).toEqual([["n-other", false], ["n-mail", true]]);
  expect(rows("relay_notes").map(row => row.id)).toEqual(["n-other"]);
  expect(bucket.objects.has(files.audio)).toBe(false);
});

it("sends note.deleted at a move, the whole note and its files at a recover, and nothing at a delete for good after a move", async () => {
  const sent: Record<string, unknown>[] = [];
  vi.stubGlobal("fetch", vi.fn(async (_url: string, init: RequestInit) => {
    const body = typeof init.body === "string" ? init.body : new TextDecoder().decode(init.body as Uint8Array);
    sent.push(JSON.parse(body) as Record<string, unknown>);
    return new Response(null, { status: 204 });
  }));
  emailed();
  // The webhook sends a file's bytes only when they open, as each stored file is sealed.
  const store = spaceOf(env() as never, vouch("session", ANA)).files;
  for (const item of ["n-mail", "attachments/f-mail"]) await store.put(item, new Uint8Array([1, 2, 3]).buffer);
  db.sql.exec(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, active, sent_seq, created_at) VALUES ('hook-1', 'Database',
    'https://hook-1.example.com/relay', 'whsec_dGVzdC1vbmx5LXNlY3JldC1mb3ItdGhlLXNlbmRlcg==', '["notes"]', 1,
    (SELECT max(seq) FROM relay_outbox), ${NOW})`);
  await move("n-mail");
  await drain();
  await recover({ id: "n-mail" });
  await drain();
  await move("n-mail");
  await call(phone, "DELETE", "notes", { id: "n-mail", forever: "true" });
  await drain();
  expect(sent.map(message => message.type)).toEqual(["note.deleted", "note.recovered", "note.file", "note.deleted"]);
  expect(sent[1]).toMatchObject({ data: { note: { id: "n-mail", text: "Flight to Lisbon", audio: { content_type: "audio/mp4", base64: "AQID" },
    attachments: [{ id: "f-mail", name: "ticket.pdf" }] } } });
  expect(sent[2]).toMatchObject({ data: { note_id: "n-mail", file: { id: "f-mail", base64: "AQID" } } });
});
