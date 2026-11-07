-- An API key: a device key that reads and adds notes through the web API. SQLite can't change a CHECK in place, so
-- relay_keys is copied into a new table with `api` in its reaches, every row kept. openspec/changes/relay-api-and-connector-add
CREATE TABLE relay_keys_new (
  key_sha256 TEXT PRIMARY KEY,
  person_id TEXT NOT NULL REFERENCES relay_people(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  reaches TEXT NOT NULL CHECK (reaches IN ('phone', 'chats', 'api')),
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  UNIQUE (person_id, device_id)
);
INSERT INTO relay_keys_new (key_sha256, person_id, device_id, reaches, created_at, revoked_at)
  SELECT key_sha256, person_id, device_id, reaches, created_at, revoked_at FROM relay_keys;
DROP TABLE relay_keys;
ALTER TABLE relay_keys_new RENAME TO relay_keys;
