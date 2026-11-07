-- What only a space holds: its file key, which seals each recording in the file store, the Pebble app's signing secret
-- for each Pebble device, and the person the space belongs to, which its webhook alarm names in each queue message.
CREATE TABLE space_keys (
  name TEXT PRIMARY KEY,
  key BLOB NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE relay_device_secrets (
  device_id TEXT PRIMARY KEY REFERENCES relay_devices(id),
  pebble_secret TEXT NOT NULL
);
CREATE TABLE space_meta (
  name TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
