-- A recording is one of a note's files, with the words the phone wrote from it, its length, and whether the note
-- started with it. openspec/changes/recordings-as-attachments
ALTER TABLE relay_attachments ADD COLUMN transcript TEXT;
ALTER TABLE relay_attachments ADD COLUMN length_ms INTEGER;
ALTER TABLE relay_attachments ADD COLUMN top INTEGER NOT NULL DEFAULT 0;

-- A new transcript moves the note's change row, so each phone's next pull gets it; PATCH notes logs its note.updated.
CREATE TRIGGER relay_note_changes_transcript AFTER UPDATE OF transcript, length_ms ON relay_attachments
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = new.note_id;
  INSERT INTO relay_note_changes (note_id) VALUES (new.note_id);
END;
