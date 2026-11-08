-- Note sync: one row per note, at its newest change, numbered in the order the changes happened. GET notes?since= reads
-- the notes whose row is past a phone's last number. openspec/changes/sync-notes-across-phones
-- AUTOINCREMENT never gives a number twice, so a note's row moved to the end always gets a higher seq than any before.
CREATE TABLE relay_note_changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  note_id TEXT NOT NULL UNIQUE REFERENCES relay_notes(id) ON DELETE CASCADE
);

-- Each trigger deletes the note's row and adds it again, not INSERT OR REPLACE: a statement that fires a trigger with
-- its own conflict clause would replace the trigger's.
CREATE TRIGGER relay_note_changes_added AFTER INSERT ON relay_notes
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = new.id;
  INSERT INTO relay_note_changes (note_id) VALUES (new.id);
END;

CREATE TRIGGER relay_note_changes_changed AFTER UPDATE OF text, lat, place, edited_at, audio_key ON relay_notes
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = new.id;
  INSERT INTO relay_note_changes (note_id) VALUES (new.id);
END;

CREATE TRIGGER relay_note_changes_file_added AFTER INSERT ON relay_attachments
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = new.note_id;
  INSERT INTO relay_note_changes (note_id) VALUES (new.note_id);
END;

CREATE TRIGGER relay_note_changes_file_ready AFTER UPDATE OF file_key ON relay_attachments
  WHEN old.file_key IS NULL AND new.file_key IS NOT NULL
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = new.note_id;
  INSERT INTO relay_note_changes (note_id) VALUES (new.note_id);
END;

-- The notes already here, oldest first, so a phone's first sync gets them in the order they were written.
INSERT INTO relay_note_changes (note_id) SELECT id FROM relay_notes ORDER BY recorded_at, id;
