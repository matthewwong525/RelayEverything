/// <reference types="node" />
import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { expect, it } from "vitest";
import { MIGRATIONS } from "../../spaces-worker";

// A new space must hold the same relay_* tables, indexes and triggers as D1, so the move copies each row unchanged.
const folder = new URL("../../../../schema/migrations/", import.meta.url);
/** The directory stays in D1, and these four only in a space. */
const DIRECTORY = ["relay_people", "relay_logins", "relay_sessions", "relay_sign_in_codes", "relay_keys", "relay_connect_codes",
  "relay_move_tickets"];
const SPACE_ONLY = ["space_migrations", "space_keys", "space_meta", "relay_device_secrets"];

/** SQL without comments or layout, so a column added by ALTER TABLE reads as one written in CREATE TABLE. */
const normal = (sql: string | null) => sql?.replace(/--[^\n]*/g, "").replace(/\s+/g, " ").replace(/\s*([(),])\s*/g, "$1").trim() ?? null;

/** Each table, index and trigger outside `skip`, by name, with its normal SQL. */
function schema(sql: DatabaseSync, skip: string[]) {
  const rows = sql.prepare("SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name").all() as
    { type: string; name: string; tbl_name: string; sql: string | null }[];
  return rows.filter(row => !skip.includes(row.tbl_name)).map(row => ({ ...row, sql: normal(row.sql) }));
}

it("makes a new space's schema equal to D1's after its relay_* migrations, but the directory and the space's own", () => {
  const d1 = new DatabaseSync(":memory:");
  const files = readdirSync(folder).filter(file => file.includes("relay") && file.endsWith(".sql")).sort();
  expect(files).toContain("20261107120000_relay_people.sql");
  for (const file of files) d1.exec(readFileSync(new URL(file, folder), "utf8"));
  const space = new DatabaseSync(":memory:");
  space.exec("CREATE TABLE space_migrations (name TEXT PRIMARY KEY, applied_at INTEGER NOT NULL)");
  for (const [, text] of MIGRATIONS) space.exec(text);
  const tables = schema(space, SPACE_ONLY);
  expect(tables.some(row => row.type === "trigger")).toBe(true);
  expect(tables).toEqual(schema(d1, DIRECTORY));
});
