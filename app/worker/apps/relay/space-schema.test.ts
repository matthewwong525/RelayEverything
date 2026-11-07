/// <reference types="node" />
import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { expect, it } from "vitest";
import { MIGRATIONS } from "../../spaces-worker";

// D1 keeps only the directory; each person's data lives in their own space. wiki/relay-spaces.md
const folder = new URL("../../../../schema/migrations/", import.meta.url);
const DIRECTORY = ["relay_people", "relay_logins", "relay_sessions", "relay_sign_in_codes", "relay_keys", "relay_connect_codes"];
const PERSON = ["relay_devices", "relay_notes", "relay_health", "relay_locations", "relay_chats", "relay_chat_messages",
  "relay_chat_saves", "relay_outbox", "relay_webhooks", "relay_webhook_attempts", "relay_photos"];

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
