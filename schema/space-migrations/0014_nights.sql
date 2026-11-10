-- Nights and full workouts: the phone groups its sleep readings into nights, per source, and sends each workout with
-- its kind, distance and calories. openspec/changes/health-nights-workouts.
CREATE TABLE relay_nights (
  id INTEGER PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  source TEXT NOT NULL,
  start_at INTEGER NOT NULL,
  end_at INTEGER NOT NULL,
  asleep_at INTEGER,
  woke_at INTEGER,
  asleep REAL NOT NULL,
  core REAL NOT NULL,
  deep REAL NOT NULL,
  rem REAL NOT NULL,
  awake REAL NOT NULL,
  stages TEXT NOT NULL DEFAULT '[]',
  updated_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, source, start_at)
);
CREATE INDEX relay_nights_end ON relay_nights(end_at);

ALTER TABLE relay_health ADD COLUMN kind TEXT;
ALTER TABLE relay_health ADD COLUMN distance REAL;
ALTER TABLE relay_health ADD COLUMN calories REAL;

-- Webhooks get health.nights: relay_outbox takes the 'night' kind. As in 0013_stays, the log waits in a copy, keeping
-- every seq, and the log triggers are made again after.
DROP TRIGGER relay_outbox_note_created;
DROP TRIGGER relay_outbox_health;
DROP TRIGGER relay_outbox_location;
DROP TRIGGER relay_outbox_calendar_created;
DROP TRIGGER relay_outbox_calendar_updated;
DROP TRIGGER relay_outbox_note_file;
DROP TRIGGER relay_outbox_photo;
DROP TRIGGER relay_outbox_stay_created;
DROP TRIGGER relay_outbox_stay_updated;

CREATE TABLE relay_outbox_copy AS SELECT seq, kind, ref, at, logged_at FROM relay_outbox;
DROP TABLE relay_outbox;
CREATE TABLE relay_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('note.created', 'note.updated', 'note.file', 'note.deleted', 'health', 'location', 'calendar', 'photo', 'stay', 'night')),
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

-- A night is logged when it comes and each time it changes, as a stay is.
CREATE TRIGGER relay_outbox_night_created AFTER INSERT ON relay_nights
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('night', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

CREATE TRIGGER relay_outbox_night_updated AFTER UPDATE ON relay_nights
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('night', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

-- A workout from before gets its kind, distance and calories once: it goes to the webhooks again with them.
CREATE TRIGGER relay_outbox_health_detail AFTER UPDATE OF kind ON relay_health
  WHEN old.kind IS NULL AND new.kind IS NOT NULL
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('health', CAST(new.id AS TEXT), new.start_at,
    CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER));
END;
