-- A note can be pinned to the top of the notes list on every device: PUT notes/pin keeps when it was pinned, NULL when it
-- is not, and when the pin last changed, so the newer change wins. openspec/changes/note-editor-pins-find
ALTER TABLE relay_notes ADD COLUMN pinned_at INTEGER;
ALTER TABLE relay_notes ADD COLUMN pin_changed_at INTEGER;

-- A pin moves the note's change row, so each phone's next pull gets it; it logs nothing, so no webhook gets a message.
CREATE TRIGGER relay_note_changes_pinned AFTER UPDATE OF pinned_at, pin_changed_at ON relay_notes
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = new.id;
  INSERT INTO relay_note_changes (note_id) VALUES (new.id);
END;
