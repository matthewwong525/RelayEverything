-- A device can now be the space's inbox (`inbox`): the *Email* device that emailed notes point at. SQLite can't
-- change a CHECK in place, so relay_devices is made again as 0003 does, with the foreign-key check deferred.
-- openspec/changes/email-notes
PRAGMA defer_foreign_keys = ON;
CREATE TABLE relay_devices_copy AS SELECT id, name, token_client_id, token_id, created_at, revoked_at, reaches FROM relay_devices;
DROP TABLE relay_devices;
CREATE TABLE relay_devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (name = trim(name) AND name != ''),
  -- `rek:` and the device's id for a key, `app:` and it for a connected app, `inbox:email` for the inbox.
  token_client_id TEXT NOT NULL UNIQUE,
  token_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  -- phone, chats and api: a key's reach; app: a connected app; inbox: mail sent to the person's notes address.
  reaches TEXT NOT NULL DEFAULT 'phone' CHECK (reaches IN ('phone', 'chats', 'api', 'app', 'inbox'))
);
INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches)
  SELECT id, name, token_client_id, token_id, created_at, revoked_at, reaches FROM relay_devices_copy;
DROP TABLE relay_devices_copy;
-- The deferred check stays on to the end of the Durable Object's transaction otherwise, so put it back now.
PRAGMA defer_foreign_keys = OFF;
