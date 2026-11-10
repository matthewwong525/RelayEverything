-- The person's memory: one table of facts, added and never changed, with the columns the server keeps fixed here and
-- the person's own columns as checked values in `fields`. Topics on facts and notes. openspec/changes/knowledge-web
CREATE TABLE relay_memory (
  -- `f` and 4 to 6 base32 letters, made by the server.
  id TEXT PRIMARY KEY CHECK (id GLOB 'f*' AND length(id) BETWEEN 5 AND 7),
  -- The person's own columns, each checked against relay_memory_columns when the fact is added.
  fields TEXT NOT NULL CHECK (json_valid(fields) AND json_type(fields) = 'object'),
  -- `relay:` links to the records the fact came from: at least one.
  sources TEXT NOT NULL CHECK (json_valid(sources) AND json_type(sources) = 'array' AND json_array_length(sources) > 0),
  replaces TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(replaces) AND json_type(replaces) = 'array'),
  -- Set once, by the fact that replaces this one, in the same transaction: the only change a fact ever gets.
  replaced_by TEXT REFERENCES relay_memory(id),
  device_id TEXT NOT NULL REFERENCES relay_devices(id),
  -- The caller's own id for the fact, so a resent batch is stored once: unique per device, as a note's is.
  client_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, client_id)
);
CREATE INDEX relay_memory_created ON relay_memory(created_at);

-- A fact's topics: `battery`, `ring/charging`. The one copy; a fact keeps at least one, which memory.ts checks.
CREATE TABLE relay_memory_tags (
  fact_id TEXT NOT NULL REFERENCES relay_memory(id),
  tag TEXT NOT NULL,
  PRIMARY KEY (fact_id, tag)
);
CREATE INDEX relay_memory_tags_tag ON relay_memory_tags(tag);

-- The person's columns. A removed column keeps its row, so its name can't come back with a new type.
CREATE TABLE relay_memory_columns (
  name TEXT PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('text', 'number', 'date', 'yes_no', 'words')),
  required INTEGER NOT NULL DEFAULT 0 CHECK (required IN (0, 1)),
  note TEXT NOT NULL DEFAULT '',
  added_at INTEGER NOT NULL,
  removed_at INTEGER
);
INSERT INTO relay_memory_columns (name, type, required, note, added_at) VALUES
  ('kind', 'text', 1, 'The kind of fact, as FORMAT.md lists them: fact, decision, preference, plan, open or reference.', 0),
  ('text', 'text', 1, 'The fact in one short sentence.', 0);

-- Each column change, with the device that made it.
CREATE TABLE relay_memory_column_changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  change TEXT NOT NULL CHECK (change IN ('add', 'change', 'remove')),
  -- The column as the change left it, as JSON.
  detail TEXT NOT NULL,
  device_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

-- A note's topics, in the same form as a fact's: they go with the note.
CREATE TABLE relay_note_tags (
  note_id TEXT NOT NULL REFERENCES relay_notes(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  PRIMARY KEY (note_id, tag)
);
CREATE INDEX relay_note_tags_tag ON relay_note_tags(tag);

-- Each tag added to or removed from a fact or a note: `link` is `relay:fact/<id>` or `relay:note/<id>`.
CREATE TABLE relay_tag_changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  link TEXT NOT NULL,
  tag TEXT NOT NULL,
  change TEXT NOT NULL CHECK (change IN ('add', 'remove')),
  device_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
