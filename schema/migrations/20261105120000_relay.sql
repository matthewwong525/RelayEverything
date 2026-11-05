-- Relay: notes from the Pebble ring and the phones, the phones' health samples and location history, and the device
-- keys that send them. openspec/changes/relay-app-first-version. Additive only. Times are Unix milliseconds.
CREATE TABLE relay_devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (name = trim(name) AND name != ''),
  -- The Access service token's Client ID, which the Worker reads as the caller's id, and its Cloudflare id.
  token_client_id TEXT NOT NULL UNIQUE,
  token_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER
);
CREATE TABLE relay_notes (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  source TEXT NOT NULL CHECK (source IN ('ring', 'typed')),
  -- A ring note's X-Index-Delivery, or a typed note's id from its phone: each is stored once.
  delivery_id TEXT UNIQUE,
  client_id TEXT,
  text TEXT NOT NULL,
  audio_key TEXT,
  recorded_at INTEGER NOT NULL,
  lat REAL,
  lon REAL,
  accuracy REAL,
  place TEXT,
  place_from TEXT CHECK (place_from IN ('phone', 'history')),
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, client_id),
  -- A place is whole or absent: the timeline reads lat alone to know.
  CHECK ((lat IS NULL) = (lon IS NULL) AND (lat IS NULL) = (place_from IS NULL))
);
CREATE INDEX relay_notes_recorded ON relay_notes(recorded_at);
CREATE TABLE relay_health (
  id INTEGER PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  type TEXT NOT NULL CHECK (type IN ('steps', 'heart_rate', 'sleep', 'workout')),
  start_at INTEGER NOT NULL,
  end_at INTEGER NOT NULL CHECK (end_at >= start_at),
  value REAL NOT NULL,
  unit TEXT NOT NULL,
  source TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, type, start_at, end_at, source)
);
CREATE INDEX relay_health_start ON relay_health(start_at);
CREATE TABLE relay_locations (
  id INTEGER PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  at INTEGER NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  accuracy REAL NOT NULL,
  place TEXT,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, at)
);
CREATE INDEX relay_locations_at ON relay_locations(at);
