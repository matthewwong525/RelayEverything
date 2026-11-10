import { Webhook } from "standardwebhooks";
import { afterEach, expect, it, vi } from "vitest";
import { ANA, BEN, benPhone, bucket, call, checker, db, env, ipad, laptop, lost, matthew, NOW, phone, queue, rows } from "../../../tests/relay";
import { consume } from "./webhooks/send.ts";

const MINUTE = 60_000;
const files = { file: `people/${ANA}/attachments/f-mail`, audio: `people/${ANA}/n-mail`, other: `people/${ANA}/attachments/f-other` };

/** An emailed note in Ana's space with a stored file and recording, and a second note whose file must stay. */
function emailed() {
  db.sql.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches)
      VALUES ('d-mail', 'Email', 'inbox:email', '', ${NOW}, 'inbox');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, audio_key, recorded_at, created_at)
      VALUES ('n-mail', 'd-mail', 'typed', 'email:m-1', 'Flight to Lisbon', '${files.audio}', ${NOW - 60 * MINUTE}, ${NOW - 60 * MINUTE}),
        ('n-other', 'd-mail', 'typed', 'email:m-2', 'Hotel', NULL, ${NOW - 30 * MINUTE}, ${NOW - 30 * MINUTE});
    INSERT INTO relay_attachments (id, note_id, name, content_type, size, file_key, created_at)
      VALUES ('f-mail', 'n-mail', 'ticket.pdf', 'application/pdf', 3, '${files.file}', ${NOW}),
        ('f-wait', 'n-mail', 'seat.pdf', 'application/pdf', 3, NULL, ${NOW}),
        ('f-other', 'n-other', 'hotel.pdf', 'application/pdf', 3, '${files.other}', ${NOW});`);
  for (const key of Object.values(files)) bucket.objects.set(key, new Uint8Array([1, 2, 3]));
}
const SECRET = "whsec_dGVzdC1vbmx5LXNlY3JldC1mb3ItdGhlLXNlbmRlcg==";
afterEach(() => { vi.unstubAllGlobals(); });
const log = () => rows("relay_outbox").map(row => [row.kind, row.ref]);

it("deletes any note in the space by id, with its files and recording, and logs one note.deleted", async () => {
  emailed();
  expect(await call(phone, "DELETE", "notes", { id: "n-mail" })).toEqual({ status: 200, json: { id: "n-mail", deleted: true } });
  expect(rows("relay_notes").map(row => row.id)).toEqual(["n-other"]);
  expect(rows("relay_attachments").map(row => row.id)).toEqual(["f-other"]);
  expect([...bucket.objects.keys()]).toEqual([files.other]);
  expect(log().at(-1)).toEqual(["note.deleted", "n-mail"]);
  // The page reads it no more, and a change or a second delete finds no note.
  expect(((await call(matthew, "GET", "timeline")).json as unknown as { notes: { id: string }[] }).notes.map(note => note.id)).toEqual(["n-other"]);
  expect(await call(ipad, "PATCH", "notes", { id: "n-mail", text: "Flight" })).toMatchObject({ status: 404, json: { error: { code: "not_found" } } });
  expect(await call(ipad, "DELETE", "notes", { id: "n-mail" })).toMatchObject({ status: 404, json: { error: { code: "not_found" } } });
  expect(log().filter(([kind]) => kind === "note.deleted")).toHaveLength(1);
});

it("deletes a phone's own note by its clientId, and only that phone's", async () => {
  await call(phone, "POST", "notes", { clientId: "note-delete-01", text: "Buy milk", createdAt: NOW - MINUTE });
  expect((await call(ipad, "DELETE", "notes", { clientId: "note-delete-01" })).status).toBe(404);
  const { json } = await call(phone, "DELETE", "notes", { clientId: "note-delete-01" });
  expect(json).toEqual({ id: expect.any(String), deleted: true });
  expect(rows("relay_notes")).toEqual([]);
  expect(log()).toEqual([["note.created", json.id], ["note.deleted", json.id]]);
});

it("refuses a delete with no note named, or with both an id and a clientId", async () => {
  emailed();
  expect((await call(phone, "DELETE", "notes")).status).toBe(400);
  expect((await call(phone, "DELETE", "notes", { id: "n-mail", clientId: "email:m-1" })).status).toBe(400);
  expect(rows("relay_notes")).toHaveLength(2);
});

it("lets no other person's phone, chat key, API key, checker or turned-off key delete a note", async () => {
  emailed();
  // Ben's phone reaches only Ben's space, which has no such note.
  expect((await call(benPhone, "DELETE", "notes", { id: "n-mail" })).status).toBe(404);
  const { json: made } = await call(matthew, "POST", "devices", { name: "Backup script", reaches: "api" });
  // The page deletes as the space's Web device: page-notes.test.ts.
  for (const who of [laptop, { bearer: String(made.key) }, lost, checker, null]) {
    const { status } = await call(who, "DELETE", "notes", { id: "n-mail" });
    expect(status === 401 || status === 403, `${JSON.stringify(who)}: ${status}`).toBe(true);
  }
  expect(rows("relay_notes").map(row => row.id)).toEqual(["n-mail", "n-other"]);
  expect(rows("relay_notes", BEN)).toEqual([]);
  expect(bucket.objects.size).toBe(3);
});

it("sends the delete to each webhook as one signed note.deleted, and never the note.created still waiting", async () => {
  const sent: { url: string; body: string; headers: Record<string, string> }[] = [];
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    sent.push({ url, body: String(init.body), headers: init.headers as Record<string, string> });
    return new Response(null, { status: 204 });
  }));
  for (const id of ["hook-1", "hook-2"]) {
    db.sql.exec(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, active, sent_seq, created_at)
      VALUES ('${id}', 'Database', 'https://${id}.example.com/relay', '${SECRET}', '["notes"]', 1, 0, ${NOW})`);
  }
  await call(phone, "POST", "notes", { clientId: "note-delete-02", text: "Order more switches", createdAt: NOW - MINUTE });
  const { json } = await call(phone, "DELETE", "notes", { clientId: "note-delete-02" });
  const messages = queue.sent.map(body => ({ body, ack: vi.fn(), retry: vi.fn() }));
  await consume({ queue: "relay-everything-webhooks", messages } as unknown as MessageBatch, env());
  expect(sent.map(item => item.url).sort()).toEqual(["https://hook-1.example.com/relay", "https://hook-2.example.com/relay"]);
  for (const item of sent) {
    expect(new Webhook(SECRET).verify(item.body, item.headers))
      .toMatchObject({ type: "note.deleted", data: { note: { id: json.id, deleted_at: expect.any(String) } } });
  }
  expect(rows("relay_webhooks").map(row => row.sent_seq)).toEqual([2, 2]);
});
