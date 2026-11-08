-- Photos from the phones: each row is one photo's time, place and size, and the name of its sealed file in the file
-- store, under people/<person id>/photos/. openspec/changes/relay-photos. Times are Unix milliseconds.
-- A staging space ran this once as 0007_photos, so each step here is safe to run again.
CREATE TABLE IF NOT EXISTS relay_photos (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  -- The phone's own id for the photo: a resend is stored once.
  client_id TEXT NOT NULL,
  taken_at INTEGER NOT NULL,
  lat REAL,
  lon REAL,
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  bytes INTEGER NOT NULL,
  file_key TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, client_id)
);
CREATE INDEX IF NOT EXISTS relay_photos_taken ON relay_photos (taken_at, id);

-- Photos go to the webhooks ticked for them: relay_outbox takes the 'photo' kind. SQLite can't change a CHECK in place,
-- so the log waits in a copy, keeping every seq (each webhook's place is a seq); the log triggers are made again after.
DROP TRIGGER IF EXISTS relay_outbox_note_created;
DROP TRIGGER IF EXISTS relay_outbox_health;
DROP TRIGGER IF EXISTS relay_outbox_location;
DROP TRIGGER IF EXISTS relay_outbox_calendar_created;
DROP TRIGGER IF EXISTS relay_outbox_calendar_updated;
DROP TRIGGER IF EXISTS relay_outbox_note_file;
DROP TRIGGER IF EXISTS relay_outbox_photo;

DROP TABLE IF EXISTS relay_outbox_copy;
CREATE TABLE relay_outbox_copy AS SELECT seq, kind, ref, at, logged_at FROM relay_outbox;
DROP TABLE relay_outbox;
CREATE TABLE relay_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('note.created', 'note.updated', 'note.file', 'health', 'location', 'calendar', 'photo')),
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

-- As 0007_note_files makes it: a file is listed with its note, so its note.created always has the lower seq.
CREATE TRIGGER relay_outbox_note_file AFTER UPDATE OF file_key ON relay_attachments
  WHEN old.file_key IS NULL AND new.file_key IS NOT NULL
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) SELECT 'note.file', new.id, n.recorded_at,
    CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER) FROM relay_notes n WHERE n.id = new.note_id;
END;

-- A resend of the same photo adds no row, so it logs nothing.
CREATE TRIGGER relay_outbox_photo AFTER INSERT ON relay_photos
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('photo', new.id, new.taken_at, new.created_at);
END;
