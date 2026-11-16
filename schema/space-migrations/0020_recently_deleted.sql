-- A deleted note waits in Recently Deleted for 30 days: deleted_at is when it moved there, NULL for a note not deleted.
-- openspec/changes/recently-deleted. relay_notes is never rebuilt: a new table cascades away every note's files.
ALTER TABLE relay_notes ADD COLUMN deleted_at INTEGER;
CREATE INDEX relay_notes_deleted ON relay_notes(deleted_at) WHERE deleted_at IS NOT NULL;

-- A move and a recover each move the note's change row, so each device's next pull gets the note's new place.
CREATE TRIGGER relay_note_changes_moved AFTER UPDATE OF deleted_at ON relay_notes
  WHEN old.deleted_at IS NOT new.deleted_at
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = new.id;
  INSERT INTO relay_note_changes (note_id) VALUES (new.id);
END;

-- Webhooks get note.recovered: relay_outbox takes the 'note.recovered' kind. As in 0014_nights, the log waits in a copy,
-- keeping every seq, and the log triggers are made again after.
DROP TRIGGER relay_outbox_note_created;
DROP TRIGGER relay_outbox_health;
DROP TRIGGER relay_outbox_location;
DROP TRIGGER relay_outbox_calendar_created;
DROP TRIGGER relay_outbox_calendar_updated;
DROP TRIGGER relay_outbox_note_file;
DROP TRIGGER relay_outbox_photo;
DROP TRIGGER relay_outbox_stay_created;
DROP TRIGGER relay_outbox_stay_updated;
DROP TRIGGER relay_outbox_night_created;
DROP TRIGGER relay_outbox_night_updated;
DROP TRIGGER relay_outbox_health_detail;

CREATE TABLE relay_outbox_copy AS SELECT seq, kind, ref, at, logged_at FROM relay_outbox;
DROP TABLE relay_outbox;
CREATE TABLE relay_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('note.created', 'note.updated', 'note.file', 'note.deleted', 'note.recovered', 'health', 'location',
    'calendar', 'photo', 'stay', 'night')),
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

CREATE TRIGGER relay_outbox_stay_created AFTER INSERT ON relay_stays
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('stay', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

CREATE TRIGGER relay_outbox_stay_updated AFTER UPDATE ON relay_stays
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('stay', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

CREATE TRIGGER relay_outbox_night_created AFTER INSERT ON relay_nights
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('night', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

CREATE TRIGGER relay_outbox_night_updated AFTER UPDATE ON relay_nights
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('night', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

CREATE TRIGGER relay_outbox_health_detail AFTER UPDATE OF kind ON relay_health
  WHEN old.kind IS NULL AND new.kind IS NOT NULL
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('health', CAST(new.id AS TEXT), new.start_at,
    CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER));
END;
