// The Recently Deleted migration, 0020: space-schema.test.ts holds the migrations before it.
import { DatabaseSync } from "node:sqlite";
import { expect, it } from "vitest";
import { MIGRATIONS } from "../../spaces-worker";

/** Runs `text` as `migrate` does: one transaction, which the deferred foreign-key check closes. */
const inTransaction = (sql: DatabaseSync, text: string) => {
  sql.exec("BEGIN");
  try { sql.exec(text); sql.exec("COMMIT"); } catch (error) { sql.exec("ROLLBACK"); throw error; }
};
const all = (sql: DatabaseSync, query: string) => sql.prepare(query).all().map(row => ({ ...row }));
const triggers = (sql: DatabaseSync) => all(sql, "SELECT name FROM sqlite_master WHERE type = 'trigger'").map(row => String(row.name)).sort();

it("adds the time a note moved to Recently Deleted, keeping every note, file, log entry, webhook place and trigger", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  const at = MIGRATIONS.findIndex(([name]) => name === "0020_recently_deleted");
  for (const [, text] of MIGRATIONS.slice(0, at)) inTransaction(space, text);
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-phone', 'Phone', 'rek:d-phone', '', 1, 'phone');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-1', 'd-phone', 'typed', 'c-1', 'One.', 5, 5),
      ('n-2', 'd-phone', 'typed', 'c-2', 'Two.', 6, 6);
    INSERT INTO relay_attachments (id, note_id, name, content_type, size, file_key, created_at)
      VALUES ('f-1', 'n-1', 'a.pdf', 'application/pdf', 3, NULL, 7);
    UPDATE relay_attachments SET file_key = 'people/x/attachments/f-1' WHERE id = 'f-1';
    INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('note.deleted', 'n-9', 4, 8);
    INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at) VALUES ('w-1', 'DB', 'https://db.example.com', 's', '["notes"]', 2, 1);`);
  const kept = ["SELECT * FROM relay_attachments", "SELECT * FROM relay_outbox ORDER BY seq", "SELECT * FROM relay_webhooks",
    "SELECT * FROM relay_note_changes ORDER BY seq"];
  const before = kept.map(query => all(space, query));
  const notes = all(space, "SELECT * FROM relay_notes ORDER BY id");
  const made = triggers(space);
  inTransaction(space, MIGRATIONS[at][1]);
  expect(kept.map(query => all(space, query))).toEqual(before);
  expect(all(space, "SELECT * FROM relay_notes ORDER BY id")).toEqual(notes.map(note => ({ ...note, deleted_at: null })));
  expect(triggers(space)).toEqual([...made, "relay_note_changes_moved"].sort());
  // A move and a recover each move the note's change row to the next seq; a second move at the same time does not.
  const last = () => all(space, "SELECT note_id, deleted FROM relay_note_changes ORDER BY seq DESC LIMIT 1")[0];
  const count = () => all(space, "SELECT seq FROM relay_note_changes").length;
  const seq = () => Number(all(space, "SELECT max(seq) AS seq FROM relay_note_changes")[0].seq);
  const start = seq();
  space.exec("UPDATE relay_notes SET deleted_at = 10 WHERE id = 'n-1'");
  expect([seq(), last()]).toEqual([start + 1, { note_id: "n-1", deleted: 0 }]);
  space.exec("UPDATE relay_notes SET deleted_at = 10 WHERE id = 'n-1'");
  expect(seq()).toBe(start + 1);
  space.exec("UPDATE relay_notes SET deleted_at = NULL WHERE id = 'n-1'");
  expect([seq(), last()]).toEqual([start + 2, { note_id: "n-1", deleted: 0 }]);
  expect(count()).toBe(2);
  // The log takes note.recovered after the kept rows, and still refuses a kind it doesn't know.
  space.exec("INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('note.recovered', 'n-1', 5, 11)");
  expect(all(space, "SELECT seq, kind FROM relay_outbox ORDER BY seq DESC LIMIT 1")).toEqual([{ seq: Number(before[1].at(-1)!.seq) + 1,
    kind: "note.recovered" }]);
  expect(() => space.exec("INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('video', 'v', 1, 1)")).toThrow(/CHECK/);
  // The log triggers still log: a new note and its sealed file.
  space.exec(`INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-3', 'd-phone', 'typed', 'c-3', 'Three.', 9, 9);
    INSERT INTO relay_attachments (id, note_id, name, content_type, size, file_key, created_at) VALUES ('f-3', 'n-3', 'b.pdf', 'application/pdf', 3, NULL, 9);
    UPDATE relay_attachments SET file_key = 'people/x/attachments/f-3' WHERE id = 'f-3';`);
  expect(all(space, "SELECT kind, ref FROM relay_outbox ORDER BY seq DESC LIMIT 2")).toEqual([{ kind: "note.file", ref: "f-3" },
    { kind: "note.created", ref: "n-3" }]);
  expect(all(space, "PRAGMA foreign_key_check")).toEqual([]);
});
