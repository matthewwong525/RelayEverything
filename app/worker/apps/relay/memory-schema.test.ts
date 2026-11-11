/// <reference types="node" />
import { DatabaseSync } from "node:sqlite";
import { expect, it } from "vitest";
import { MIGRATIONS } from "../../spaces-worker";

// The memory's step on a space that holds notes already: wiki/stack/relay-knowledge-web.md#the-memory
const inTransaction = (sql: DatabaseSync, text: string) => {
  sql.exec("BEGIN");
  try { sql.exec(text); sql.exec("COMMIT"); } catch (error) { sql.exec("ROLLBACK"); throw error; }
};
const all = (sql: DatabaseSync, query: string) => sql.prepare(query).all().map(row => ({ ...row }));

it("adds the memory with its two first columns, and topics on facts and notes that go with a deleted note", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  const at = MIGRATIONS.findIndex(([name]) => name === "0016_memory");
  for (const [, text] of MIGRATIONS.slice(0, at)) inTransaction(space, text);
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-mac', 'Mac', 'rek:d-mac', '', 1, 'agent');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at) VALUES ('n-1', 'd-mac', 'typed', 'c-1', 'Charger cable.', 5, 5);`);
  const before = all(space, "SELECT * FROM relay_notes");
  inTransaction(space, MIGRATIONS[at][1]);
  expect(all(space, "SELECT * FROM relay_notes")).toEqual(before);
  expect(all(space, "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('relay_memory', 'relay_memory_tags', 'relay_memory_columns', 'relay_memory_column_changes', 'relay_note_tags', 'relay_tag_changes')")).toHaveLength(6);
  expect(all(space, "SELECT name, type, required FROM relay_memory_columns ORDER BY name"))
    .toEqual([{ name: "kind", type: "text", required: 1 }, { name: "text", type: "text", required: 1 }]);
  space.exec(`INSERT INTO relay_memory (id, fields, sources, device_id, client_id, created_at)
      VALUES ('fab2c', '{"kind":"decision","text":"Battery stays 40 mAh."}', '["relay:chat/7f3a#120"]', 'd-mac', 'c-1', 6);
    INSERT INTO relay_memory_tags (fact_id, tag) VALUES ('fab2c', 'battery');
    INSERT INTO relay_note_tags (note_id, tag) VALUES ('n-1', 'bike/charging');`);
  for (const [sources, fields, client] of [["[]", "{}", "c-2"], ['["relay:note/n-1"]', "[]", "c-3"], ['["relay:note/n-1"]', "{}", "c-1"]]) {
    expect(() => space.prepare("INSERT INTO relay_memory (id, fields, sources, device_id, client_id, created_at) VALUES ('fzzzz', ?, ?, 'd-mac', ?, 7)")
      .run(fields, sources, client)).toThrow(/CHECK|UNIQUE/);
  }
  expect(() => space.exec("INSERT INTO relay_memory_columns (name, type, added_at) VALUES ('mood', 'emoji', 1)")).toThrow(/CHECK/);
  space.exec("DELETE FROM relay_notes WHERE id = 'n-1'");
  expect(all(space, "SELECT * FROM relay_note_tags")).toEqual([]);
  expect(all(space, "PRAGMA foreign_key_check")).toEqual([]);
});
