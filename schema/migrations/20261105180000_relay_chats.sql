-- Relay chats: Claude Code chats sent by a key that can only add chats, each message kept once in order, and the AI's
-- own title and summary for a chat. openspec/changes/relay-claude-plugin. Additive only. Times are Unix milliseconds.
-- A key's reach: a phone or the Pebble app reaches the notes routes; a chat key reaches only the chat sends.
ALTER TABLE relay_devices ADD COLUMN reaches TEXT NOT NULL DEFAULT 'phone' CHECK (reaches IN ('phone', 'chats'));
CREATE TABLE relay_chats (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  -- Claude Code's own session id: one chat per key and session.
  session_id TEXT NOT NULL,
  app TEXT NOT NULL DEFAULT 'claude-code' CHECK (app = 'claude-code'),
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
