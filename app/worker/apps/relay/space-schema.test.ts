/// <reference types="node" />
import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import { expect, it } from "vitest";
import { migrate, MIGRATIONS } from "../../spaces-worker";

// D1 keeps only the directory; each person's data lives in their own space. wiki/relay-spaces.md
const folder = new URL("../../../../schema/migrations/", import.meta.url);
const DIRECTORY = ["relay_people", "relay_logins", "relay_sessions", "relay_sign_in_codes", "relay_keys", "relay_connect_codes"];
const PERSON = ["relay_devices", "relay_notes", "relay_health", "relay_locations", "relay_chats", "relay_chat_messages",
  "relay_chat_saves", "relay_outbox", "relay_webhooks", "relay_webhook_attempts", "relay_attachments"];

const tables = (sql: DatabaseSync) => (sql.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'relay\\_%' ESCAPE '\\'")
  .all() as { name: string }[]).map(row => row.name).sort();

it("leaves a new D1 with the directory and none of the old shared tables after every migration", () => {
  const d1 = new DatabaseSync(":memory:");
  d1.exec("PRAGMA foreign_keys = ON");
  for (const file of readdirSync(folder).filter(file => file.endsWith(".sql")).sort()) d1.exec(readFileSync(new URL(file, folder), "utf8"));
  expect(tables(d1)).toEqual([...DIRECTORY].sort());
});

it("gives a new space each person's tables and none of the directory's", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  for (const [, text] of MIGRATIONS) space.exec(text);
  expect(tables(space)).toEqual([...PERSON, "relay_device_secrets"].sort());
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
  for (const [name, text] of MIGRATIONS.slice(0, 2)) {
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
