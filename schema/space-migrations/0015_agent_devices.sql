-- A device can now be a computer's key (`agent`): it saves AI chats and reads through the web API. A chat now names
-- the app it came from, Claude Code or Codex. SQLite can't change a CHECK in place, so relay_devices is made again as
-- 0009 does, and the three chat tables are made again with the children first: dropping relay_chats while its
-- messages point at it would delete them by their ON DELETE CASCADE. openspec/changes/agent-plugin-and-mcp-address
PRAGMA defer_foreign_keys = ON;
CREATE TABLE relay_devices_copy AS SELECT id, name, token_client_id, token_id, created_at, revoked_at, reaches FROM relay_devices;
CREATE TABLE relay_chats_copy AS SELECT * FROM relay_chats;
CREATE TABLE relay_chat_messages_copy AS SELECT * FROM relay_chat_messages;
CREATE TABLE relay_chat_saves_copy AS SELECT * FROM relay_chat_saves;
DROP TABLE relay_chat_messages;
DROP TABLE relay_chat_saves;
DROP TABLE relay_chats;
DROP TABLE relay_devices;
CREATE TABLE relay_devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (name = trim(name) AND name != ''),
  -- `rek:` and the device's id for a key, `app:` and it for a connected app, `inbox:email` for the inbox.
  token_client_id TEXT NOT NULL UNIQUE,
  token_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  -- phone, chats, api and agent: a key's reach; app: a connected app; inbox: mail sent to the person's notes address.
  reaches TEXT NOT NULL DEFAULT 'phone' CHECK (reaches IN ('phone', 'chats', 'api', 'app', 'inbox', 'agent'))
);
INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches)
  SELECT id, name, token_client_id, token_id, created_at, revoked_at, reaches FROM relay_devices_copy;
CREATE TABLE relay_chats (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  -- The app's own session id: one chat per key and session.
  session_id TEXT NOT NULL,
  -- The app the chat came from, as its first send named it.
  app TEXT NOT NULL DEFAULT 'claude-code' CHECK (app IN ('claude-code', 'codex')),
  -- The project's folder name, never its full path.
  project TEXT NOT NULL,
  -- The title at the first send; a later send never changes it, and the newest save's title shows over it.
  title TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  last_at INTEGER NOT NULL,
  message_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, session_id)
);
CREATE INDEX relay_chats_last ON relay_chats(last_at);
CREATE TABLE relay_chat_messages (
  chat_id TEXT NOT NULL REFERENCES relay_chats(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL CHECK (seq >= 0),
  role TEXT NOT NULL CHECK (role IN ('you', 'ai', 'step')),
  text TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (chat_id, seq)
);
CREATE TABLE relay_chat_saves (
  id TEXT PRIMARY KEY,
  chat_id TEXT NOT NULL REFERENCES relay_chats(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX relay_chat_saves_chat ON relay_chat_saves(chat_id, created_at);
INSERT INTO relay_chats (id, device_id, session_id, app, project, title, started_at, last_at, message_count, created_at)
  SELECT id, device_id, session_id, app, project, title, started_at, last_at, message_count, created_at FROM relay_chats_copy;
INSERT INTO relay_chat_messages (chat_id, seq, role, text, at) SELECT chat_id, seq, role, text, at FROM relay_chat_messages_copy;
INSERT INTO relay_chat_saves (id, chat_id, title, text, created_at) SELECT id, chat_id, title, text, created_at FROM relay_chat_saves_copy;
DROP TABLE relay_chat_saves_copy;
DROP TABLE relay_chat_messages_copy;
DROP TABLE relay_chats_copy;
DROP TABLE relay_devices_copy;
-- The deferred check stays on to the end of the Durable Object's transaction otherwise, so put it back now.
PRAGMA defer_foreign_keys = OFF;
