/// <reference types="node" />
import { DatabaseSync } from "node:sqlite";
import { expect, it } from "vitest";
import { MIGRATIONS } from "../../spaces-worker";

// The step that moves each note's place into location history: openspec/changes/note-places-in-history
const inTransaction = (sql: DatabaseSync, text: string) => {
  sql.exec("BEGIN");
  try { sql.exec(text); sql.exec("COMMIT"); } catch (error) { sql.exec("ROLLBACK"); throw error; }
};
const all = (sql: DatabaseSync, query: string) => sql.prepare(query).all().map(row => ({ ...row }));

it("moves each note's place into location history once, sends no webhook message, and keeps the note's files and change row", () => {
  const space = new DatabaseSync(":memory:");
  space.exec("PRAGMA foreign_keys = ON");
  const at = MIGRATIONS.findIndex(([name]) => name === "0017_note_places");
  for (const [, text] of MIGRATIONS.slice(0, at)) inTransaction(space, text);
  space.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at) VALUES ('d-phone', 'Phone', 'rek:d-phone', '', 1);
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, lat, lon, accuracy, place, place_from, created_at) VALUES
      ('n-1', 'd-phone', 'typed', 'c-1', 'Bought milk.', 1000, 43.6, -79.4, 12, 'Queen St W', 'phone', 1000),
      ('n-2', 'd-phone', 'typed', 'c-2', 'Call Sam back.', 2000, 43.7, -79.3, NULL, NULL, 'phone', 2000),
      ('n-3', 'd-phone', 'typed', 'c-3', 'Point already there.', 3000, 1, 2, 5, 'Note place', 'phone', 3000),
      ('n-4', 'd-phone', 'typed', 'c-4', 'No place.', 4000, NULL, NULL, NULL, NULL, NULL, 4000);
    INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, place, created_at) VALUES ('d-phone', 3000, 9, 9, 50, 'Kept', 3000);
    INSERT INTO relay_attachments (id, note_id, name, content_type, size, created_at) VALUES ('a-1', 'n-1', 'milk.jpg', 'image/jpeg', 10, 1000);`);
  const outbox = all(space, "SELECT * FROM relay_outbox ORDER BY seq");
  const changes = all(space, "SELECT * FROM relay_note_changes ORDER BY seq");
  inTransaction(space, MIGRATIONS[at][1]);
  expect(all(space, "SELECT at, lat, lon, accuracy, place FROM relay_locations ORDER BY at")).toEqual([
    { at: 1000, lat: 43.6, lon: -79.4, accuracy: 12, place: "Queen St W" }, { at: 2000, lat: 43.7, lon: -79.3, accuracy: 0, place: null },
    { at: 3000, lat: 9, lon: 9, accuracy: 50, place: "Kept" }]);
  expect(all(space, "SELECT count(*) AS placed FROM relay_notes WHERE lat IS NOT NULL OR lon IS NOT NULL OR accuracy IS NOT NULL OR place IS NOT NULL OR place_from IS NOT NULL"))
    .toEqual([{ placed: 0 }]);
  expect(all(space, "SELECT * FROM relay_outbox ORDER BY seq")).toEqual(outbox);
  expect(all(space, "SELECT * FROM relay_note_changes ORDER BY seq")).toEqual(changes);
  expect(all(space, "SELECT id, note_id FROM relay_attachments")).toEqual([{ id: "a-1", note_id: "n-1" }]);
  // A new point still goes to the webhooks, and a note's words still count as a change.
  space.exec("INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, created_at) VALUES ('d-phone', 5000, 1, 1, 1, 5000)");
  space.exec("UPDATE relay_notes SET text = 'Bought oat milk.' WHERE id = 'n-1'");
  expect(all(space, "SELECT kind FROM relay_outbox WHERE seq > (SELECT max(seq) FROM relay_outbox) - 1")).toEqual([{ kind: "location" }]);
  expect(all(space, "SELECT note_id FROM relay_note_changes ORDER BY seq DESC LIMIT 1")).toEqual([{ note_id: "n-1" }]);
  expect(all(space, "PRAGMA foreign_key_check")).toEqual([]);
});
