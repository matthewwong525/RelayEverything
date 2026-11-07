-- The person's Google connection: one row, holding their Google address, the permissions Google gave, and the refresh
-- token sealed with the space's file key. No email, event, file or contact is kept. openspec/changes/google-mail-calendar
CREATE TABLE relay_google (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  email TEXT NOT NULL,
  scopes TEXT NOT NULL,
  token BLOB NOT NULL,
  connected_at INTEGER NOT NULL
);
