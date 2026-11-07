-- A note's files: one row per file, listed when its note arrives, with file_key NULL until the phone sends the bytes.
-- The bytes are sealed in the file store under people/<person>/attachments/<id>, as a recording is.
CREATE TABLE relay_attachments (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL REFERENCES relay_notes(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  content_type TEXT NOT NULL,
  size INTEGER NOT NULL CHECK (size >= 0),
  file_key TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX relay_attachments_note ON relay_attachments(note_id);
