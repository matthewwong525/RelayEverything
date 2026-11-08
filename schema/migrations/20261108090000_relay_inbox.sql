-- Email notes: each person's secret notes address, found by an HMAC of its local part, and mail kept sealed for an
-- email with no account yet, until it signs up or 30 days pass. openspec/changes/email-notes
CREATE TABLE relay_inbox_links (
  channel TEXT NOT NULL CHECK (channel IN ('email')),
  sender_hmac TEXT NOT NULL,
  person_id TEXT NOT NULL REFERENCES relay_people(id) ON DELETE CASCADE,
  -- The local part the person's card shows; mail is found only by the HMAC.
  shown TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (channel, sender_hmac),
  UNIQUE (person_id, channel)
);
-- One kept mail, sealed with a key made from the sender's email, which the server does not store. Its files are
-- in the bucket under held/<sender_hmac>/<id>/.
CREATE TABLE relay_inbox_held (
  id TEXT PRIMARY KEY,
  channel TEXT NOT NULL CHECK (channel IN ('email')),
  sender_hmac TEXT NOT NULL,
  sent_at INTEGER NOT NULL,
  size INTEGER NOT NULL,
  body TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX relay_inbox_held_sender ON relay_inbox_held (channel, sender_hmac, created_at);
CREATE INDEX relay_inbox_held_age ON relay_inbox_held (created_at);
