/// <reference types="node" />
import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import { expect, it } from "vitest";
import { migrate, MIGRATIONS } from "../../spaces-worker";

// D1 keeps only the directory; each person's data lives in their own space. wiki/relay-spaces.md
const folder = new URL("../../../../schema/migrations/", import.meta.url);
const DIRECTORY = ["relay_people", "relay_logins", "relay_sessions", "relay_sign_in_codes", "relay_keys", "relay_connect_codes",
  "relay_phone_codes"];
const PERSON = ["relay_devices", "relay_notes", "relay_health", "relay_locations", "relay_chats", "relay_chat_messages",
  "relay_chat_saves", "relay_outbox", "relay_webhooks", "relay_webhook_attempts", "relay_attachments", "relay_calendar_events", "relay_photos"];

const tables = (sql: DatabaseSync) => (sql.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'relay\\_%' ESCAPE '\\'")
  .all() as { name: string }[]).map(row => row.name).sort();

it("leaves a new D1 with the directory and none of the old shared tables after every migration", () => {
  const d1 = new DatabaseSync(":memory:");
  d1.exec("PRAGMA foreign_keys = ON");
  for (const file of readdirSync(folder).filter(file => file.endsWith(".sql")).sort()) d1.exec(readFileSync(new URL(file, folder), "utf8"));
  expect(tables(d1)).toEqual([...DIRECTORY].sort());
});

const triggers = (sql: DatabaseSync) => (sql.prepare("SELECT name FROM sqlite_master WHERE type = 'trigger'").all() as { name: string }[])
  .map(row => row.name);

it("gives a new space each person's tables and none of the directory's, with no signing secret or late place", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  for (const [, text] of MIGRATIONS) space.exec(text);
  expect(tables(space)).toEqual([...PERSON].sort());
  expect(triggers(space)).not.toContain("relay_outbox_note_updated");
  expect(triggers(space)).toContain("relay_outbox_note_created");
});

it("gives a space made before files the files table, once, and keeps its notes", () => {
  const sql = new DatabaseSync(":memory:");
  sql.exec("PRAGMA foreign_keys = ON");
  // A Durable Object's storage, as much of it as migrate uses.
  const run = (query: string, params: SQLInputValue[]) => /^\s*SELECT/i.test(query) ? sql.prepare(query).all(...params)
    : params.length ? (sql.prepare(query).run(...params), []) : (sql.exec(query), []);
  const storage = { sql: { exec: (query: string, ...params: SQLInputValue[]) => { const rows = run(query, params); return { toArray: () => rows }; } },
    transactionSync: <T>(run: () => T) => run() } as unknown as Parameters<typeof migrate>[0];
  sql.exec("CREATE TABLE space_migrations (name TEXT PRIMARY KEY, applied_at INTEGER NOT NULL)");
  for (const [name, text] of MIGRATIONS.slice(0, 3)) {
    sql.exec(text);
    sql.prepare("INSERT INTO space_migrations VALUES (?, 0)").run(name);
  }
  sql.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at) VALUES ('d-phone', 'Phone', 'c', '', 0);
    INSERT INTO relay_notes (id, device_id, source, text, recorded_at, created_at) VALUES ('n1', 'd-phone', 'typed', 'Kept', 0, 0)`);
  migrate(storage);
  migrate(storage);
  expect(tables(sql)).toContain("relay_attachments");
  expect(sql.prepare("SELECT name FROM space_migrations ORDER BY name").all().map(row => row.name)).toEqual(MIGRATIONS.map(([name]) => name));
  expect(sql.prepare("SELECT text FROM relay_notes").all()).toEqual([{ text: "Kept" }]);
});

/** Runs `text` as `migrate` does: one transaction, which the deferred foreign-key check closes. */
const inTransaction = (sql: DatabaseSync, text: string) => {
  sql.exec("BEGIN");
  try { sql.exec(text); sql.exec("COMMIT"); } catch (error) { sql.exec("ROLLBACK"); throw error; }
};
const all = (sql: DatabaseSync, query: string) => sql.prepare(query).all().map(row => ({ ...row }));
const KEEP = ["SELECT * FROM relay_devices ORDER BY id", "SELECT * FROM relay_notes ORDER BY id", "SELECT * FROM relay_device_secrets",
  "SELECT * FROM relay_chats", "SELECT id, device_id FROM relay_health", "SELECT id, device_id FROM relay_locations"];

it("widens a space's devices to API keys and connected apps, keeping every device and what points at it", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  const at = MIGRATIONS.findIndex(([name]) => name === "0003_api_devices");
  const last = MIGRATIONS[at];
  for (const [, text] of MIGRATIONS.slice(0, at)) inTransaction(space, text);
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches) VALUES
      ('d-phone', 'Phone', 'rek:d-phone', '', 1, NULL, 'phone'), ('d-laptop', 'Laptop', 'rek:d-laptop', '', 2, 3, 'chats');
    INSERT INTO relay_device_secrets (device_id, pebble_secret) VALUES ('d-phone', 'secret');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-1', 'd-phone', 'typed', 'c-1', 'Hi.', 5, 5);
    INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES ('d-phone', 'steps', 1, 2, 9, 'count', 'fit', 1);
    INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, created_at) VALUES ('d-phone', 1, 43, -79, 5, 1);
    INSERT INTO relay_chats (id, device_id, session_id, project, title, started_at, last_at, created_at) VALUES ('c-1', 'd-laptop', 's-1', 'ring', 'Ring', 1, 2, 2);`);
  const before = KEEP.map(query => all(space, query));
  expect(() => space.exec("INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('x', 'X', 'rek:x', '', 1, 'api')"))
    .toThrow(/CHECK/);
  inTransaction(space, last[1]);
  expect(KEEP.map(query => all(space, query))).toEqual(before);
  expect(all(space, "PRAGMA foreign_key_check")).toEqual([]);
  expect(tables(space)).toEqual([...PERSON.filter(name => !["relay_attachments", "relay_calendar_events", "relay_photos"].includes(name)), "relay_device_secrets"].sort());
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-api', 'Script', 'rek:d-api', '', 1, 'api'),
    ('d-app', 'Claude', 'app:d-app', '', 1, 'app')`);
  // The table still guards its notes: a note from no device, or a made-up reach, is refused.
  expect(() => space.exec("INSERT INTO relay_notes (id, device_id, source, text, recorded_at, created_at) VALUES ('n-2', 'nobody', 'typed', 'x', 1, 1)"))
    .toThrow(/FOREIGN KEY/);
  expect(() => space.exec("INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('y', 'Y', 'rek:y', '', 1, 'web')"))
    .toThrow(/CHECK/);
});

it("frees health types and adds the calendar, keeping every health row, log entry and webhook place", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  const at = MIGRATIONS.findIndex(([name]) => name === "0006_phone_data");
  for (const [, text] of MIGRATIONS.slice(0, at)) inTransaction(space, text);
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-phone', 'Phone', 'rek:d-phone', '', 1, 'phone');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-1', 'd-phone', 'typed', 'c-1', 'Hi.', 5, 5);
    INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES ('d-phone', 'steps', 1, 2, 9, 'count', 'fit', 1),
      ('d-phone', 'sleep', 3, 4, 1, 'min', 'fit', 1);
    INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at) VALUES ('w-1', 'DB', 'https://db.example.com', 's', '["notes"]', 2, 1);`);
  expect(() => space.exec("INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES ('d-phone', 'weight', 1, 1, 70, 'kg', 'fit', 1)"))
    .toThrow(/CHECK/);
  const queries = ["SELECT * FROM relay_health ORDER BY id", "SELECT * FROM relay_outbox ORDER BY seq", "SELECT * FROM relay_notes", "SELECT * FROM relay_webhooks"];
  const before = queries.map(query => all(space, query));
  inTransaction(space, MIGRATIONS[at][1]);
  expect(queries.map(query => all(space, query))).toEqual(before);
  expect(all(space, "PRAGMA foreign_key_check")).toEqual([]);
  expect(tables(space)).toEqual(PERSON.filter(name => name !== "relay_photos").sort());
  // Every log trigger is back, numbering on from the kept entries, and the log takes the calendar.
  space.exec(`INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES ('d-phone', 'weight', 6, 6, 70, 'kg', 'fit', 6);
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-2', 'd-phone', 'typed', 'c-2', 'Again.', 7, 7);
    INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, created_at) VALUES ('d-phone', 8, 43, -79, 5, 8);
    INSERT INTO relay_calendar_events (device_id, event_key, title, start_at, end_at, updated_at, created_at) VALUES ('d-phone', 'k', 'Lunch', 9, 10, 9, 9);
    UPDATE relay_calendar_events SET removed_at = 11, updated_at = 11;`);
  expect(all(space, "SELECT seq, kind, ref FROM relay_outbox WHERE seq > 3 ORDER BY seq")).toEqual([{ seq: 4, kind: "health", ref: "3" },
    { seq: 5, kind: "note.created", ref: "n-2" }, { seq: 6, kind: "location", ref: "1" }, { seq: 7, kind: "calendar", ref: "1" },
    { seq: 8, kind: "calendar", ref: "1" }]);
  expect(() => space.exec("INSERT INTO relay_calendar_events (device_id, event_key, start_at, end_at, updated_at, created_at) VALUES ('nobody', 'k2', 1, 2, 1, 1)"))
    .toThrow(/FOREIGN KEY/);
});

it("adds photos and logs each new one for the webhooks, keeping every log entry, webhook place and log trigger", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  const at = MIGRATIONS.findIndex(([name]) => name === "0007_photos");
  for (const [, text] of MIGRATIONS.slice(0, at)) inTransaction(space, text);
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-phone', 'Phone', 'rek:d-phone', '', 1, 'phone');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-1', 'd-phone', 'typed', 'c-1', 'Hi.', 5, 5);
    INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at) VALUES ('w-1', 'DB', 'https://db.example.com', 's', '["notes"]', 1, 1);`);
  const queries = ["SELECT * FROM relay_outbox ORDER BY seq", "SELECT * FROM relay_webhooks"];
  const before = queries.map(query => all(space, query));
  expect(before[0]).toEqual([{ seq: 1, kind: "note.created", ref: "n-1", at: 5, logged_at: 5 }]);
  inTransaction(space, MIGRATIONS[at][1]);
  expect(queries.map(query => all(space, query))).toEqual(before);
  space.exec(`INSERT INTO relay_photos (id, device_id, client_id, taken_at, width, height, bytes, file_key, created_at) VALUES ('p-2', 'd-phone', 'c-2', 6, 1, 1, 1, 'k2', 7);
    INSERT INTO relay_photos (id, device_id, client_id, taken_at, width, height, bytes, file_key, created_at) VALUES ('p-3', 'd-phone', 'c-2', 6, 1, 1, 1, 'k3', 7)
      ON CONFLICT (device_id, client_id) DO NOTHING;
    INSERT INTO relay_health (device_id, type, start_at, end_at, value, unit, source, created_at) VALUES ('d-phone', 'steps', 8, 9, 9, 'count', 'fit', 9);
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-2', 'd-phone', 'typed', 'c-2', 'Again.', 10, 10);
    INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, created_at) VALUES ('d-phone', 11, 43, -79, 5, 11);
    INSERT INTO relay_calendar_events (device_id, event_key, title, start_at, end_at, updated_at, created_at) VALUES ('d-phone', 'k', 'Lunch', 12, 13, 12, 12);
    UPDATE relay_calendar_events SET removed_at = 14, updated_at = 14;`);
  expect(all(space, "SELECT seq, kind, ref, at FROM relay_outbox WHERE seq > 1 ORDER BY seq")).toEqual([{ seq: 2, kind: "photo", ref: "p-2", at: 6 },
    { seq: 3, kind: "health", ref: "1", at: 8 }, { seq: 4, kind: "note.created", ref: "n-2", at: 10 }, { seq: 5, kind: "location", ref: "1", at: 11 },
    { seq: 6, kind: "calendar", ref: "1", at: 12 }, { seq: 7, kind: "calendar", ref: "1", at: 12 }]);
  expect(() => space.exec("INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('video', 'v', 1, 1)")).toThrow(/CHECK/);
  expect(all(space, "PRAGMA foreign_key_check")).toEqual([]);
});

it("widens the directory's keys to API keys, keeping every key", () => {
  const d1 = new DatabaseSync(":memory:");
  d1.exec("PRAGMA foreign_keys = ON");
  const files = readdirSync(folder).filter(file => file.endsWith(".sql")).sort();
  const last = files.indexOf("20261107210000_relay_api_keys.sql");
  for (const file of files.slice(0, last)) d1.exec(readFileSync(new URL(file, folder), "utf8"));
  d1.exec(`INSERT INTO relay_people (id, email, created_at) VALUES ('p-1', 'ana@example.com', 1);
    INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at, revoked_at) VALUES ('k-1', 'p-1', 'd-1', 'phone', 1, NULL),
      ('k-2', 'p-1', 'd-2', 'chats', 2, 3)`);
  const before = all(d1, "SELECT * FROM relay_keys ORDER BY key_sha256");
  for (const file of files.slice(last)) d1.exec(readFileSync(new URL(file, folder), "utf8"));
  expect(all(d1, "SELECT * FROM relay_keys ORDER BY key_sha256")).toEqual(before);
  d1.exec("INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at) VALUES ('k-3', 'p-1', 'd-3', 'api', 4)");
  expect(() => d1.exec("INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at) VALUES ('k-4', 'p-1', 'd-4', 'app', 4)")).toThrow(/CHECK/);
  // A person's keys still go with the person.
  d1.exec("DELETE FROM relay_people WHERE id = 'p-1'");
  expect(all(d1, "SELECT * FROM relay_keys")).toEqual([]);
});

it("drops a space's signing secrets and its late-place trigger, keeping its ring notes and a waiting note.updated", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  const at = MIGRATIONS.findIndex(([name]) => name === "0005_no_pebble");
  for (const [, text] of MIGRATIONS.slice(0, at)) inTransaction(space, text);
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at) VALUES ('d-phone', 'iPad', 'rek:d-phone', '', 1);
    INSERT INTO relay_device_secrets (device_id, pebble_secret) VALUES ('d-phone', 'secret');
    INSERT INTO relay_notes (id, device_id, source, delivery_id, text, recorded_at, created_at) VALUES ('n-1', 'd-phone', 'ring', 'r-1', 'Ring.', 5, 5);
    UPDATE relay_notes SET lat = 43, lon = -79, place_from = 'history' WHERE id = 'n-1';`);
  const waiting = all(space, "SELECT kind, ref FROM relay_outbox ORDER BY seq");
  expect(waiting).toEqual([{ kind: "note.created", ref: "n-1" }, { kind: "note.updated", ref: "n-1" }]);
  inTransaction(space, MIGRATIONS[at][1]);
  expect(tables(space)).not.toContain("relay_device_secrets");
  expect(triggers(space)).not.toContain("relay_outbox_note_updated");
  expect(all(space, "SELECT kind, ref FROM relay_outbox ORDER BY seq")).toEqual(waiting);
  expect(all(space, "SELECT id, source, lat, lon, place_from FROM relay_notes")).toEqual([{ id: "n-1", source: "ring", lat: 43, lon: -79, place_from: "history" }]);
  // A place set now logs nothing.
  space.exec("INSERT INTO relay_notes (id, device_id, source, delivery_id, text, recorded_at, created_at) VALUES ('n-2', 'd-phone', 'ring', 'r-2', 'Old.', 6, 6)");
  space.exec("UPDATE relay_notes SET lat = 1, lon = 1, place_from = 'history' WHERE id = 'n-2'");
  expect(all(space, "SELECT kind FROM relay_outbox WHERE ref = 'n-2'")).toEqual([{ kind: "note.created" }]);
  expect(all(space, "PRAGMA foreign_key_check")).toEqual([]);
});
