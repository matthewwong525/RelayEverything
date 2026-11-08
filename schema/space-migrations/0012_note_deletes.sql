-- A deleted note keeps its change row, marked deleted and moved to a new number, so each phone's next pull drops it.
-- openspec/changes/delete-notes-everywhere. SQLite can't drop a foreign key in place, so the rows wait in a copy.
DROP TRIGGER relay_note_changes_added;
DROP TRIGGER relay_note_changes_changed;
DROP TRIGGER relay_note_changes_file_added;
DROP TRIGGER relay_note_changes_file_ready;

CREATE TABLE relay_note_changes_copy AS SELECT seq, note_id FROM relay_note_changes;
DROP TABLE relay_note_changes;
-- No foreign key: the row of a deleted note stays, with deleted = 1 and the sending phone's client_id, so that phone
-- finds the note it sent before a pull gave it the note's id.
CREATE TABLE relay_note_changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  note_id TEXT NOT NULL UNIQUE,
  deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)),
  client_id TEXT
);
-- Each seq goes back as it was, and AUTOINCREMENT goes on past the largest, above every phone's last number.
INSERT INTO relay_note_changes (seq, note_id) SELECT seq, note_id FROM relay_note_changes_copy ORDER BY seq;
DROP TABLE relay_note_changes_copy;

-- As 0011_note_sync makes them, plus one for a delete.
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

CREATE TRIGGER relay_note_changes_deleted AFTER DELETE ON relay_notes
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = old.id;
  INSERT INTO relay_note_changes (note_id, deleted, client_id) VALUES (old.id, 1, old.client_id);
END;

-- Webhooks get note.deleted: relay_outbox takes the 'note.deleted' kind. As in 0008_photos, the log waits in a copy,
-- keeping every seq (each webhook's place is a seq), and the log triggers are made again after.
DROP TRIGGER relay_outbox_note_created;
DROP TRIGGER relay_outbox_health;
DROP TRIGGER relay_outbox_location;
DROP TRIGGER relay_outbox_calendar_created;
DROP TRIGGER relay_outbox_calendar_updated;
DROP TRIGGER relay_outbox_note_file;
DROP TRIGGER relay_outbox_photo;

CREATE TABLE relay_outbox_copy AS SELECT seq, kind, ref, at, logged_at FROM relay_outbox;
DROP TABLE relay_outbox;
CREATE TABLE relay_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('note.created', 'note.updated', 'note.file', 'note.deleted', 'health', 'location', 'calendar', 'photo')),
  ref TEXT NOT NULL,
  at INTEGER NOT NULL,
  logged_at INTEGER NOT NULL
);
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

CREATE TRIGGER relay_outbox_note_file AFTER UPDATE OF file_key ON relay_attachments
  WHEN old.file_key IS NULL AND new.file_key IS NOT NULL
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT 'note.file', new.id, n.recorded_at,
    CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER) FROM relay_notes n WHERE n.id = new.note_id;
END;

CREATE TRIGGER relay_outbox_photo AFTER INSERT ON relay_photos
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('photo', new.id, new.taken_at, new.created_at);
END;
