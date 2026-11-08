-- A note can change from the phone that sent it: PATCH notes keeps the new words and the time of the change, in Unix ms.
-- NULL for a note never changed. openspec/changes/apple-notes-editing
ALTER TABLE relay_notes ADD COLUMN edited_at INTEGER;
