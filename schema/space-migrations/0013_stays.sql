-- Stays and trips: the phone works them out from its points and sends each once per start, again when it changes.
-- openspec/changes/places-timeline. A stay has a place and a name; a trip has a mode and a distance.
CREATE TABLE relay_stays (
  id INTEGER PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  kind TEXT NOT NULL CHECK (kind IN ('stay', 'trip')),
  start_at INTEGER NOT NULL,
  end_at INTEGER NOT NULL,
  ongoing INTEGER NOT NULL DEFAULT 0 CHECK (ongoing IN (0, 1)),
  lat REAL,
  lon REAL,
  name TEXT,
  address TEXT,
  event TEXT,
  source TEXT CHECK (source IN ('calendar', 'map', 'street', 'point')),
  mode TEXT,
  km REAL,
  updated_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, kind, start_at)
);
CREATE INDEX relay_stays_start ON relay_stays(start_at);

-- Webhooks get location.stays: relay_outbox takes the 'stay' kind. As in 0012_note_deletes, the log waits in a copy,
-- keeping every seq, and the log triggers are made again after.
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
  kind TEXT NOT NULL CHECK (kind IN ('note.created', 'note.updated', 'note.file', 'note.deleted', 'health', 'location', 'calendar', 'photo', 'stay')),
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

-- A stay is logged when it comes and each time it changes, as a calendar event is.
CREATE TRIGGER relay_outbox_stay_created AFTER INSERT ON relay_stays
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('stay', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

CREATE TRIGGER relay_outbox_stay_updated AFTER UPDATE ON relay_stays
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('stay', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;
