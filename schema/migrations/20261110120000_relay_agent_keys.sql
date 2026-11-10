-- A computer's key (`agent`): it saves AI chats and reads and adds through the web API. SQLite can't change a CHECK in
-- place, so relay_keys is copied into a new table with `agent` in its reaches, every row kept. And a computer's
-- sign-in by link: the computer keeps a secret whose SHA-256 is `challenge`; the person confirms the link, and the
-- computer trades the secret for its key within 10 minutes. openspec/changes/agent-plugin-and-mcp-address
CREATE TABLE relay_keys_new (
  key_sha256 TEXT PRIMARY KEY,
  person_id TEXT NOT NULL REFERENCES relay_people(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  reaches TEXT NOT NULL CHECK (reaches IN ('phone', 'chats', 'api', 'agent')),
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  UNIQUE (person_id, device_id)
);
INSERT INTO relay_keys_new (key_sha256, person_id, device_id, reaches, created_at, revoked_at)
  SELECT key_sha256, person_id, device_id, reaches, created_at, revoked_at FROM relay_keys;
DROP TABLE relay_keys;
ALTER TABLE relay_keys_new RENAME TO relay_keys;
CREATE TABLE relay_computer_codes (
  challenge TEXT PRIMARY KEY,
  -- The short code the computer and the confirm page both show, such as KITE-4821.
  words TEXT NOT NULL,
  name TEXT NOT NULL,
  -- Empty until the person clicks Connect.
  person_id TEXT REFERENCES relay_people(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);
CREATE INDEX relay_computer_codes_person ON relay_computer_codes(person_id);
