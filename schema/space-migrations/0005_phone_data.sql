-- The phone's calendar, and health types the code checks instead of a CHECK. relay_health loses its type CHECK, so a
-- new type needs no table rebuild; relay_outbox takes the 'calendar' kind. SQLite can't change a CHECK in place, so
-- each table waits in a copy while it is made again, keeping every id: the send log points at health rows by id, and
-- each webhook's place is a log seq. The triggers that write the log are made again after it.
-- openspec/changes/phone-calendar-health-meetings
DROP TRIGGER relay_outbox_note_created;
DROP TRIGGER relay_outbox_note_updated;
DROP TRIGGER relay_outbox_health;
DROP TRIGGER relay_outbox_location;

CREATE TABLE relay_health_copy AS SELECT id, device_id, type, start_at, end_at, value, unit, source, created_at FROM relay_health;
DROP TABLE relay_health;
CREATE TABLE relay_health (
  id INTEGER PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  -- One of HEALTH_TYPES in app/worker/apps/relay/queries.ts: POST health checks it.
  type TEXT NOT NULL,
  start_at INTEGER NOT NULL,
  end_at INTEGER NOT NULL CHECK (end_at >= start_at),
  value REAL NOT NULL,
  unit TEXT NOT NULL,
  source TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, type, start_at, end_at, source)
);
INSERT INTO relay_health (id, device_id, type, start_at, end_at, value, unit, source, created_at)
  SELECT id, device_id, type, start_at, end_at, value, unit, source, created_at FROM relay_health_copy ORDER BY id;
DROP TABLE relay_health_copy;
CREATE INDEX relay_health_start ON relay_health(start_at);

CREATE TABLE relay_outbox_copy AS SELECT seq, kind, ref, at, logged_at FROM relay_outbox;
DROP TABLE relay_outbox;
CREATE TABLE relay_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('note.created', 'note.updated', 'health', 'location', 'calendar')),
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

-- A ring note gets its place later, from a location batch: the webhook hears of it once, when the place arrives.
CREATE TRIGGER relay_outbox_note_updated AFTER UPDATE OF lat ON relay_notes
WHEN old.lat IS NULL AND new.lat IS NOT NULL
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at)
    VALUES ('note.updated', new.id, new.recorded_at, CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER));
END;

CREATE TRIGGER relay_outbox_health AFTER INSERT ON relay_health
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('health', CAST(new.id AS TEXT), new.start_at, new.created_at);
END;

CREATE TRIGGER relay_outbox_location AFTER INSERT ON relay_locations
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('location', CAST(new.id AS TEXT), new.at, new.created_at);
END;

-- The phone's calendar events: one row per occurrence and device, by the phone's key `<calendar>:<event>:<start ms>`.
-- POST calendar changes a row only when a field differs, and marks a removed one with removed_at; reads skip those.
-- `people` is a JSON list of {name?, email?, organizer?}.
CREATE TABLE relay_calendar_events (
  id INTEGER PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  event_key TEXT NOT NULL,
  calendar TEXT,
  title TEXT,
  start_at INTEGER NOT NULL,
  end_at INTEGER NOT NULL CHECK (end_at >= start_at),
  all_day INTEGER NOT NULL DEFAULT 0,
  location TEXT,
  notes TEXT,
  url TEXT,
  people TEXT NOT NULL DEFAULT '[]',
  removed_at INTEGER,
  updated_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, event_key)
);
CREATE INDEX relay_calendar_events_start ON relay_calendar_events(start_at);

-- A new event and each change or removal go to the webhooks that take the calendar; a resend changes no row.
CREATE TRIGGER relay_outbox_calendar_created AFTER INSERT ON relay_calendar_events
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('calendar', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;

CREATE TRIGGER relay_outbox_calendar_updated AFTER UPDATE ON relay_calendar_events
BEGIN
  INSERT INTO relay_outbox (kind, ref, at, logged_at) VALUES ('calendar', CAST(new.id AS TEXT), new.start_at, new.updated_at);
END;
