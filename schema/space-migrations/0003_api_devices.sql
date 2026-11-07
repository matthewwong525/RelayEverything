-- A device can now be an API key (`api`) or a connected app (`app`), each of which adds notes. SQLite can't change a
-- CHECK in place, and other tables point at relay_devices, so its rows wait in a copy while the table is made again:
-- each row put back meets the notes, samples and chats that point at it, and the deferred foreign-key check finds no
-- orphan at the end. openspec/changes/relay-api-and-connector-add
PRAGMA defer_foreign_keys = ON;
CREATE TABLE relay_devices_copy AS SELECT id, name, token_client_id, token_id, created_at, revoked_at, reaches FROM relay_devices;
DROP TABLE relay_devices;
CREATE TABLE relay_devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (name = trim(name) AND name != ''),
  -- `rek:` and the device's id for a key, `app:` and it for a connected app.
  token_client_id TEXT NOT NULL UNIQUE,
  token_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  -- phone: notes, health and places; chats: Claude Code chats; api: the web API's key; app: a connected app.
  reaches TEXT NOT NULL DEFAULT 'phone' CHECK (reaches IN ('phone', 'chats', 'api', 'app'))
);
INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches)
  SELECT id, name, token_client_id, token_id, created_at, revoked_at, reaches FROM relay_devices_copy;
DROP TABLE relay_devices_copy;
-- The deferred check stays on to the end of the Durable Object's transaction otherwise, so put it back now.
PRAGMA defer_foreign_keys = OFF;
