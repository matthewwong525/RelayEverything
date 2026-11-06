-- Relay Everything's directory: who has an account, how they sign in, and which device key belongs to whom. It holds no
-- note, sample, place, chat or recording: each person's data is in their own space. openspec/changes/relay-person-spaces.
-- Additive only. Times are Unix milliseconds. Codes, sessions and keys are kept only as SHA-256 fingerprints.

-- A person. `id` is random and names their space, so a changed email keeps its space.
CREATE TABLE relay_people (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE CHECK (email = lower(trim(email)) AND email != ''),
  created_at INTEGER NOT NULL
);

-- A Sign in with Apple or Google account, by the provider's own subject, for the person with the same email.
CREATE TABLE relay_logins (
  provider TEXT NOT NULL CHECK (provider IN ('apple', 'google')),
  subject TEXT NOT NULL,
  person_id TEXT NOT NULL REFERENCES relay_people(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (provider, subject)
);
CREATE INDEX relay_logins_person ON relay_logins(person_id);

-- A signed-in browser: the cookie's fingerprint, kept 30 days.
CREATE TABLE relay_sessions (
  token_sha256 TEXT PRIMARY KEY,
  person_id TEXT NOT NULL REFERENCES relay_people(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX relay_sessions_person ON relay_sessions(person_id);

-- The one live email code for an address: 10 minutes, 5 tries, then gone.
CREATE TABLE relay_sign_in_codes (
  email TEXT PRIMARY KEY,
  code_sha256 TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  tries INTEGER NOT NULL DEFAULT 0
);

-- A device key: only adds data to its person's space. `device_id` is the device's row in that space.
CREATE TABLE relay_keys (
  key_sha256 TEXT PRIMARY KEY,
  person_id TEXT NOT NULL REFERENCES relay_people(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  reaches TEXT NOT NULL CHECK (reaches IN ('phone', 'chats')),
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  UNIQUE (person_id, device_id)
);

-- A single-use code the sign-in hands the AI connector, which trades it for the person within 5 minutes.
CREATE TABLE relay_connect_codes (
  code_sha256 TEXT PRIMARY KEY,
  person_id TEXT NOT NULL REFERENCES relay_people(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);

-- A ticket for the one-time move of the owner's old data into their space: scripts/relay-move-to-space.mjs writes it
-- with the deploy key, and it lasts an hour.
CREATE TABLE relay_move_tickets (
  token_sha256 TEXT PRIMARY KEY,
  expires_at INTEGER NOT NULL
);
