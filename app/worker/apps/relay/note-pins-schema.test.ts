/// <reference types="node" />
import { DatabaseSync } from "node:sqlite";
import { expect, it } from "vitest";
import { MIGRATIONS } from "../../spaces-worker";

// The step that gives each note a pin: openspec/changes/note-editor-pins-find
const inTransaction = (sql: DatabaseSync, text: string) => {
  sql.exec("BEGIN");
  try { sql.exec(text); sql.exec("COMMIT"); } catch (error) { sql.exec("ROLLBACK"); throw error; }
};
const all = (sql: DatabaseSync, query: string) => sql.prepare(query).all().map(row => ({ ...row }));

it("gives each note a pin, empty before, moved to a higher seq by a pin change, which logs nothing", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  const at = MIGRATIONS.findIndex(([name]) => name === "0018_note_pins");
  for (const [, text] of MIGRATIONS.slice(0, at)) inTransaction(space, text);
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-phone', 'Phone', 'rek:d-phone', '', 1, 'phone');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-1', 'd-phone', 'typed', 'c-1', 'One.', 5, 5),
      ('n-2', 'd-phone', 'typed', 'c-2', 'Two.', 6, 6);`);
  const queries = ["SELECT * FROM relay_outbox ORDER BY seq", "SELECT seq, note_id FROM relay_note_changes ORDER BY seq"];
  const before = queries.map(query => all(space, query));
  inTransaction(space, MIGRATIONS[at][1]);
  expect(queries.map(query => all(space, query))).toEqual(before);
  expect(all(space, "SELECT id, pinned_at, pin_changed_at FROM relay_notes ORDER BY id")).toEqual([
    { id: "n-1", pinned_at: null, pin_changed_at: null }, { id: "n-2", pinned_at: null, pin_changed_at: null }]);
  const outbox = all(space, "SELECT * FROM relay_outbox ORDER BY seq");
  space.exec("UPDATE relay_notes SET pinned_at = 9, pin_changed_at = 9 WHERE id = 'n-1'");
  expect(all(space, "SELECT seq, note_id FROM relay_note_changes ORDER BY seq").at(-1)).toEqual({ seq: 3, note_id: "n-1" });
  space.exec("UPDATE relay_notes SET pinned_at = NULL, pin_changed_at = 10 WHERE id = 'n-1'");
  expect(all(space, "SELECT seq, note_id FROM relay_note_changes ORDER BY seq")).toEqual([{ seq: 2, note_id: "n-2" }, { seq: 4, note_id: "n-1" }]);
  expect(all(space, "SELECT * FROM relay_outbox ORDER BY seq")).toEqual(outbox);
  expect(all(space, "PRAGMA foreign_key_check")).toEqual([]);
});
