import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { expect, it } from "vitest";
import { handleApp } from "../../index";
import { call, db, env, NOW, phone, queue, request, rows } from "../../../../tests/relay";

const migration = (file: string) => readFileSync(new URL(`../../../../../schema/migrations/${file}`, import.meta.url), "utf8");
const log = () => rows("relay_outbox").map(row => [row.kind, row.ref, row.at]);
const MINUTE = 60_000;

it("logs a stored note, sample and point once, in the same write, and gives a stored ring note no place", async () => {
  db.sql.prepare(`INSERT INTO relay_notes (id, device_id, source, delivery_id, text, recorded_at, created_at)
    VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'd-ipad', 'ring', 'delivery-1', 'Ring note', ?, ?)`).run(NOW - 5 * MINUTE, NOW);
  const note = { clientId: "note-0001", text: "Typed", createdAt: NOW - MINUTE };
  await call(phone, "POST", "notes", note);
  await call(phone, "POST", "notes", note);
  const sample = { type: "steps", start: NOW - 60 * MINUTE, end: NOW - 30 * MINUTE, value: 1200, unit: "count", source: "Health Connect" };
  await call(phone, "POST", "health", { samples: [sample] });
  await call(phone, "POST", "health", { samples: [sample] });
  await call(phone, "POST", "locations", { points: [{ at: NOW - 4 * MINUTE, lat: 43.65, lon: -79.38, accuracy: 10 }] });
  // A point at the ring note's own time gives it no place, and logs no note.updated.
  await call(phone, "POST", "locations", { points: [{ at: NOW - 5 * MINUTE, lat: 43.66, lon: -79.39, accuracy: 10 }] });
  const typed = rows("relay_notes")[1].id;
  expect(log()).toEqual([
    ["note.created", "aaaaaaaa-0000-4000-8000-000000000001", NOW - 5 * MINUTE], ["note.created", typed, NOW - MINUTE],
    ["health", "1", NOW - 60 * MINUTE], ["location", "1", NOW - 4 * MINUTE], ["location", "2", NOW - 5 * MINUTE]]);
  expect(rows("relay_outbox").map(row => row.logged_at)).toEqual([NOW, NOW, NOW, NOW, NOW]);
  expect(rows("relay_notes")[0]).toMatchObject({ lat: null, lon: null, place_from: null });
});

it("logs what was stored before the migration, in time order", () => {
  const sql = new DatabaseSync(":memory:");
  sql.exec(migration("20261105120000_relay.sql"));
  sql.exec("INSERT INTO relay_devices VALUES ('d-phone', 'Android phone', 'phone.access', 't1', 0, NULL)");
  sql.exec(`INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES
    ('note-late', 'd-phone', 'typed', 'c1', 'Late', 3000000000000, 3000000000001),
    ('note-early', 'd-phone', 'typed', 'c2', 'Early', 1000000000000, 1000000000001)`);
  sql.exec(`INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at)
    VALUES ('d-phone', 'steps', 2000000000000, 2000000000000, 1, 'count', 'phone', 2000000000005)`);
  sql.exec("INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, created_at) VALUES ('d-phone', 1500000000000, 1, 2, 3, 1500000000009)");
  sql.exec(migration("20261106120000_relay_webhooks.sql"));
  expect(sql.prepare("SELECT seq, kind, ref, at, logged_at FROM relay_outbox ORDER BY seq").all().map(row => ({ ...row }))).toEqual([
    { seq: 1, kind: "note.created", ref: "note-early", at: 1000000000000, logged_at: 1000000000001 },
    { seq: 2, kind: "location", ref: "1", at: 1500000000000, logged_at: 1500000000009 },
    { seq: 3, kind: "health", ref: "1", at: 2000000000000, logged_at: 2000000000005 },
    { seq: 4, kind: "note.created", ref: "note-late", at: 3000000000000, logged_at: 3000000000001 }]);
});

it("logs a note's file once its bytes are stored, after the note, and wakes the webhooks for it", async () => {
  const files = [{ id: "file-pdf-0001", name: "warranty.pdf", type: "application/pdf", size: 3 },
    { id: "file-png-0001", name: "receipt.png", type: "image/png", size: 3 }];
  await call(phone, "POST", "notes", { clientId: "note-files-01", text: "Receipt", createdAt: NOW - MINUTE, attachments: files });
  queue.sent = [];
  db.sql.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at)
    VALUES ('hook-1', 'DB', 'https://db.example.com', 's', '["notes"]', 1, ?)`).run(NOW);
  const upload = () => handleApp(request(phone, "POST", "https://relay.example.com/apps/relay/api/attachments", { body: new Uint8Array([1, 2, 3]),
    headers: { "Content-Type": "application/pdf", "X-Note-Client-Id": "note-files-01", "X-Attachment-Id": "file-pdf-0001" } }), env(), null);
  expect((await upload()).status).toBe(200);
  expect((await upload()).status).toBe(200);
  const note = rows("relay_notes")[0].id;
  // The second file is listed but never sent, so it logs nothing.
  expect(log()).toEqual([["note.created", note, NOW - MINUTE], ["note.file", "file-pdf-0001", NOW - MINUTE]]);
  expect(queue.sent).toEqual([{ webhook: "hook-1", person: expect.any(String) }]);
});
