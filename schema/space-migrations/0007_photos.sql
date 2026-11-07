-- Photos from the phones: each row is one photo's time, place and size, and the name of its sealed file in the file
-- store, under people/<person id>/photos/. openspec/changes/relay-photos. Times are Unix milliseconds.
CREATE TABLE relay_photos (
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
CREATE INDEX relay_photos_taken ON relay_photos (taken_at, id);
