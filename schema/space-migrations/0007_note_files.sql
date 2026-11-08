-- A note's files go to webhooks: relay_outbox takes the 'note.file' kind, logged when a file's bytes are sealed, at its
-- note's time, so "Send past data" picks a file with its note. SQLite can't change a CHECK in place, so the log waits
-- in a copy while it is made again, keeping every seq: each webhook's place is a log seq. The log triggers are made
-- again after it. openspec/changes/webhook-note-files
DROP TRIGGER relay_outbox_note_created;
DROP TRIGGER relay_outbox_health;
DROP TRIGGER relay_outbox_location;
DROP TRIGGER relay_outbox_calendar_created;
DROP TRIGGER relay_outbox_calendar_updated;

CREATE TABLE relay_outbox_copy AS SELECT seq, kind, ref, at, logged_at FROM relay_outbox;
DROP TABLE relay_outbox;
CREATE TABLE relay_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('note.created', 'note.updated', 'note.file', 'health', 'location', 'calendar')),
  ref TEXT NOT NULL,
  at INTEGER NOT NULL,
  logged_at INTEGER NOT NULL
);
-- Putting each seq back moves the AUTOINCREMENT counter past the largest, so no seq is used twice.
INSERT INTO relay_outbox (seq, kind, ref, at, logged_at) SELECT seq, kind, ref, at, logged_at FROM relay_outbox_copy ORDER BY seq;
DROP TABLE relay_outbox_copy;
CREATE INDEX relay_outbox_at ON relay_outbox(at);

CREATE TRIGGER relay_outbox_note_created AFTER INSERT ON relay_notes
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('note.created', new.id, new.recorded_at, new.created_at);
END;

CREATE TRIGGER relay_outbox_health AFTER INSERT ON relay_health
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('health', CAST(new.id AS TEXT), new.start_at, new.created_at);
END;

CREATE TRIGGER relay_outbox_location AFTER INSERT ON relay_locations
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('location', CAST(new.id AS TEXT), new.at, new.created_at);
END;

CREATE TRIGGER relay_outbox_calendar_created AFTER INSERT ON relay_calendar_events
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('calendar', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

CREATE TRIGGER relay_outbox_calendar_updated AFTER UPDATE ON relay_calendar_events
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('calendar', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

-- A file is listed with its note, so its note.created always has the lower seq. julianday works on every SQLite.
CREATE TRIGGER relay_outbox_note_file AFTER UPDATE OF file_key ON relay_attachments
  WHEN old.file_key IS NULL AND new.file_key IS NOT NULL
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT 'note.file', new.id, n.recorded_at,
    CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER) FROM relay_notes n WHERE n.id = new.note_id;
END;

-- Each file stored before this goes once, in its note's order.
INSERT INTO relay_outbox (kind, ref, at, logged_at)
  SELECT 'note.file', a.id, n.recorded_at, CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
  FROM relay_attachments a JOIN relay_notes n ON n.id = a.note_id WHERE a.file_key IS NOT NULL ORDER BY n.recorded_at, a.rowid;
