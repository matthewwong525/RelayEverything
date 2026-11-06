// The one-time move: the owner's old D1 rows and recordings go into their own space, once, with counts to check.
import { beforeEach, expect, test } from "vitest";
import { bucket, directoryDb, env, NOW, queue, spaces } from "../../../tests/relay";
import { move } from "./move";
import { hashToken } from "./people";
import { spaceOf, vouch } from "./space";

const TICKET = "move-ticket-0123456789abcdef";
const AUDIO = new TextEncoder().encode("plain ring audio");

const moveEnv = (more: object = {}) => env({ WONG_OWNER_EMAIL: "Owner@Example.com", ...more }) as never;
async function post(body: unknown, { ticket = TICKET, more = {} }: { ticket?: string | null; more?: object } = {}) {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (ticket) headers.Authorization = `Bearer ${ticket}`;
  const response = await move(new Request("https://relay.example.com/apps/relay/move", { method: "POST", headers, body: JSON.stringify(body) }), moveEnv(more));
  return { status: response.status, json: await response.json() as Record<string, unknown> };
}
/** Every table, a page at a time, as the script asks. */
async function moveAll() {
  const answers = [];
  for (const table of ["relay_devices", "relay_notes", "relay_health", "relay_locations", "relay_chats", "relay_chat_messages", "relay_chat_saves", "relay_webhooks"]) {
    for (let after: number | null = 0; after !== null;) {
      const { status, json } = await post({ table, after });
      expect(status).toBe(200);
      answers.push(json);
      after = json.next as number | null;
    }
  }
  return answers;
}
const ownerId = () => (directoryDb.sql.prepare("SELECT id FROM relay_people WHERE email = 'owner@example.com'").get() as { id: string }).id;

beforeEach(async () => {
  const old = directoryDb.sql;
  old.prepare("INSERT INTO relay_move_tickets (token_sha256, expires_at) VALUES (?, ?)").run(await hashToken(TICKET), NOW + 60_000);
  old.prepare("INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-old', 'Old phone', 'old.access', 't', ?, 'phone')").run(NOW);
  const note = old.prepare(`INSERT INTO relay_notes (id, device_id, source, delivery_id, text, audio_key, recorded_at, created_at)
    VALUES (?, 'd-old', 'ring', ?, 'a note', ?, ?, ?)`);
  note.run("n-audio", "x1", "notes/n-audio.m4a", NOW - 3000, NOW);
  note.run("n-gone", "x2", "notes/n-gone.m4a", NOW - 2000, NOW);
  note.run("n-text", "x3", null, NOW - 1000, NOW);
  const health = old.prepare("INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES ('d-old', 'steps', ?, ?, 10, 'count', 'phone', ?)");
  for (let index = 0; index < 205; index++) health.run(NOW - index * 60_000, NOW - index * 60_000, NOW);
  old.prepare("INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, created_at) VALUES ('d-old', ?, 1, 2, 5, ?)").run(NOW, NOW);
  old.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, pending_seq, created_at)
    VALUES ('w-old', 'Home', 'https://hooks.example.com/in', 'whsec', '["notes"]', 2, 3, ?)`).run(NOW);
  bucket.objects.set("notes/n-audio.m4a", AUDIO);
});

test("the move copies every table into the owner's space, a page at a time, with counts that match", async () => {
  const answers = await moveAll();
  const health = answers.filter(answer => answer.table === "relay_health");
  expect(health.map(answer => [answer.read, answer.added, answer.next])).toEqual([[200, 200, 200], [5, 5, null]]);
  expect(answers.find(answer => answer.table === "relay_notes")).toMatchObject({ read: 3, added: 3, missingFiles: 1, next: null });
  const { json } = await post({ counts: true });
  expect(json.space).toEqual(json.old);
  expect(json.old).toMatchObject({ relay_devices: 1, relay_notes: 3, relay_health: 205, relay_locations: 1, relay_webhooks: 1 });
});

test("a second run adds nothing and seals no recording again", async () => {
  await moveAll();
  const puts = bucket.put.mock.calls.length;
  const again = await moveAll();
  expect(again.every(answer => answer.added === 0 && answer.missingFiles === 0)).toBe(true);
  expect(bucket.put.mock.calls.length).toBe(puts);
});

test("a recording is sealed into the owner's folder, and a gone one leaves its note with none", async () => {
  await moveAll();
  const person = ownerId();
  const notes = spaces.sql(person).prepare("SELECT id, audio_key FROM relay_notes ORDER BY id").all();
  expect(notes).toEqual([{ id: "n-audio", audio_key: `people/${person}/n-audio` }, { id: "n-gone", audio_key: null }, { id: "n-text", audio_key: null }]);
  expect(bucket.objects.get(`people/${person}/n-audio`)).not.toEqual(AUDIO);
  const files = spaceOf(env() as never, vouch("move", person)).files;
  expect(await files.open(`people/${person}/n-audio`)).toEqual(AUDIO);
  // The old object stays until the owner checks the counts.
  expect(bucket.objects.has("notes/n-audio.m4a")).toBe(true);
});

test("a moved webhook starts at the end of the space's log, so the moved notes are not sent again", async () => {
  await moveAll();
  const person = ownerId();
  const webhook = spaces.sql(person).prepare("SELECT sent_seq, pending_seq, secret FROM relay_webhooks").get();
  const end = spaces.sql(person).prepare("SELECT max(seq) AS seq FROM relay_outbox").get() as { seq: number };
  expect(end.seq).toBe(3 + 205 + 1);
  expect(webhook).toEqual({ sent_seq: end.seq, pending_seq: null, secret: "whsec" });
  expect(spaces.alarmOf(person)).not.toBeNull();
  await spaces.alarm(person);
  expect(queue.sent).toEqual([]);
});

test("a missing, wrong or expired ticket is refused, and nothing moves", async () => {
  expect((await post({ counts: true }, { ticket: null })).status).toBe(403);
  expect((await post({ counts: true }, { ticket: "wrong-ticket-0123456789abcdef" })).status).toBe(403);
  directoryDb.sql.prepare("UPDATE relay_move_tickets SET expires_at = ?").run(NOW);
  expect(await post({ table: "relay_notes", after: 0 })).toMatchObject({ status: 403, json: { error: { message: "This move ticket is wrong or has expired." } } });
  expect(directoryDb.sql.prepare("SELECT count(*) AS count FROM relay_people").get()).toEqual({ count: 2 });
});

test("a server with no owner email, or a body it can't read, moves nothing", async () => {
  expect(await post({ counts: true }, { more: { WONG_OWNER_EMAIL: undefined } })).toMatchObject({ status: 409, json: { error: { message: "No owner email is set." } } });
  expect((await post({ table: "relay_outbox", after: 0 })).status).toBe(400);
  expect((await post({ table: "relay_notes", after: -1 })).status).toBe(400);
  const response = await move(new Request("https://relay.example.com/apps/relay/move", { method: "POST",
    headers: { Authorization: `Bearer ${TICKET}` }, body: "not json" }), moveEnv());
  expect(response.status).toBe(400);
});
