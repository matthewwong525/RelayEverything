/// <reference types="node" />
import { DatabaseSync } from "node:sqlite";
import { expect, it } from "vitest";
import { MIGRATIONS } from "../../spaces-worker";

// The step that gives each file a transcript, a length and a top: openspec/changes/recordings-as-attachments
const inTransaction = (sql: DatabaseSync, text: string) => {
  sql.exec("BEGIN");
  try { sql.exec(text); sql.exec("COMMIT"); } catch (error) { sql.exec("ROLLBACK"); throw error; }
};
const all = (sql: DatabaseSync, query: string) => sql.prepare(query).all().map(row => ({ ...row }));

it("gives each file an empty transcript and length, top 0, and moves the note's change row on a new transcript", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  const at = MIGRATIONS.findIndex(([name]) => name === "0021_recording_transcripts");
  for (const [, text] of MIGRATIONS.slice(0, at)) inTransaction(space, text);
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-phone', 'Phone', 'rek:d-phone', '', 1, 'phone');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-1', 'd-phone', 'typed', 'c-1', '', 5, 5),
      ('n-2', 'd-phone', 'typed', 'c-2', 'Two.', 6, 6);
    INSERT INTO relay_attachments (id, note_id, name, content_type, size, created_at) VALUES ('f-1', 'n-1', 'Recording.wav', 'audio/wav', 9, 5);`);
  const queries = ["SELECT * FROM relay_outbox ORDER BY seq", "SELECT seq, note_id FROM relay_note_changes ORDER BY seq"];
  const before = queries.map(query => all(space, query));
  inTransaction(space, MIGRATIONS[at][1]);
  expect(queries.map(query => all(space, query))).toEqual(before);
  expect(all(space, "SELECT id, transcript, length_ms, top FROM relay_attachments")).toEqual([
    { id: "f-1", transcript: null, length_ms: null, top: 0 }]);
  const outbox = all(space, "SELECT * FROM relay_outbox ORDER BY seq");
  space.exec("UPDATE relay_attachments SET transcript = 'Call the fab.', length_ms = 4200 WHERE id = 'f-1'");
  expect(all(space, "SELECT seq, note_id FROM relay_note_changes ORDER BY seq")).toEqual([{ seq: 2, note_id: "n-2" }, { seq: 4, note_id: "n-1" }]);
  // The change row moves; the note.updated is PATCH notes' to log, not the trigger's.
  expect(all(space, "SELECT * FROM relay_outbox ORDER BY seq")).toEqual(outbox);
  expect(all(space, "PRAGMA foreign_key_check")).toEqual([]);
});
