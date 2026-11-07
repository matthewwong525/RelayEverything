-- A phone's one-time sign-in code: the person confirms *Connect this phone?*, and the app trades the code, with the
-- secret whose SHA-256 is `challenge`, for its own device key within 5 minutes. Additive only; times are Unix ms.
CREATE TABLE relay_phone_codes (
  code_sha256 TEXT PRIMARY KEY,
  person_id TEXT NOT NULL REFERENCES relay_people(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  challenge TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX relay_phone_codes_person ON relay_phone_codes(person_id);
