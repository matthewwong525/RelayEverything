-- A person's space: today's relay_* schema, as D1 holds it after 20261105120000_relay.sql, 20261105180000_relay_chats.sql
-- and 20261106120000_relay_webhooks.sql, copied in that order. Each space runs it once, in its own SQLite.
-- app/worker/spaces-worker.ts. A test compares the result with D1's: space-schema.test.ts.

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

-- Relay webhooks: a send log every stored row joins in the same write, and the webhooks that read it, each at its own
-- place. openspec/changes/relay-webhooks. Additive only. Times are Unix milliseconds.

-- One row per thing a webhook may send, in the order Relay stored them. Triggers below fill it, so a stored row and its
-- log entry commit together or not at all. `at` is the item's own time, which past data is chosen by; `logged_at` is
-- when Relay stored it, which a message's timestamp shows. Never pruned: about 40 bytes a row.
CREATE TABLE relay_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('note.created', 'note.updated', 'health', 'location')),
  ref TEXT NOT NULL,
  at INTEGER NOT NULL,
  logged_at INTEGER NOT NULL
);
CREATE INDEX relay_outbox_at ON relay_outbox(at);

-- What Relay stored before this migration, in time order, so Send past data reaches it.
INSERT INTO relay_outbox (kind, ref, at, logged_at)
  SELECT kind, ref, at, logged_at FROM (
    SELECT 'note.created' AS kind, id AS ref, recorded_at AS at, created_at AS logged_at FROM relay_notes
    UNION ALL SELECT 'health', CAST(id AS TEXT), start_at, created_at FROM relay_health
    UNION ALL SELECT 'location', CAST(id AS TEXT), at, created_at FROM relay_locations)
  ORDER BY at, kind, ref;

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

-- An address the owner added. `kinds` is a JSON list of "notes", "health" and "locations"; notes are always in it.
-- `sent_seq` is the last log entry the address accepted. `pending_seq` is the last entry of the group being tried, so
-- every retry sends the same group. `tries`, `next_try_at` and `failing_since` follow a failing address;
-- `backfill_seq` is the log's end when past data was asked for. `secret` signs each message and never leaves the server
-- after it is shown once.
CREATE TABLE relay_webhooks (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (name = trim(name) AND name != ''),
  url TEXT NOT NULL,
  secret TEXT NOT NULL,
  kinds TEXT NOT NULL CHECK (json_valid(kinds)),
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  sent_seq INTEGER NOT NULL,
  pending_seq INTEGER,
  backfill_seq INTEGER,
  lease_until INTEGER,
  tries INTEGER NOT NULL DEFAULT 0,
  next_try_at INTEGER,
  failing_since INTEGER,
  last_status INTEGER,
  last_error TEXT,
  last_sent_at INTEGER,
  created_at INTEGER NOT NULL
);

-- Each try to reach a webhook, kept 30 days for its card. A test has no log entries.
CREATE TABLE relay_webhook_attempts (
  id INTEGER PRIMARY KEY,
  webhook_id TEXT NOT NULL REFERENCES relay_webhooks(id) ON DELETE CASCADE,
  at INTEGER NOT NULL,
  first_seq INTEGER,
  last_seq INTEGER,
  type TEXT NOT NULL,
  status INTEGER,
  ms INTEGER NOT NULL,
  error TEXT
);
CREATE INDEX relay_webhook_attempts_webhook ON relay_webhook_attempts(webhook_id, at);
CREATE INDEX relay_webhook_attempts_at ON relay_webhook_attempts(at);
