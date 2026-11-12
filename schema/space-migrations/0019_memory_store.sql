-- WongStack memory's store in the person's space: what each fact needs, set once when it is added, and memory's sessions,
-- runs and topic definitions. No row's words change. openspec/changes/relay-memory-plugin

-- Memory's number for each fact, beside its `f…` id: the older facts in the order they came, by created_at, then id.
ALTER TABLE relay_memory ADD COLUMN n INTEGER;
UPDATE relay_memory SET n = (SELECT count(*) FROM relay_memory o WHERE o.created_at < relay_memory.created_at
  OR (o.created_at = relay_memory.created_at AND o.id <= relay_memory.id));
CREATE UNIQUE INDEX relay_memory_n ON relay_memory(n);
-- Memory's change or conversation slug, and its session, such as claude:<uuid>.
ALTER TABLE relay_memory ADD COLUMN slug TEXT;
ALTER TABLE relay_memory ADD COLUMN session_id TEXT;
CREATE INDEX relay_memory_session ON relay_memory(session_id);
-- The email that wrote the fact through the store; null for the daily build's own facts.
ALTER TABLE relay_memory ADD COLUMN author TEXT;
-- The person's id; null for a team fact. The store sets it on the build's older facts on its first use.
ALTER TABLE relay_memory ADD COLUMN owner_subject TEXT;
ALTER TABLE relay_memory ADD COLUMN shared INTEGER NOT NULL DEFAULT 1 CHECK (shared IN (0, 1));
-- Memory's own sources, as it wrote them: `session:<id>`, a path or a link. `sources` keeps the `relay:` links.
ALTER TABLE relay_memory ADD COLUMN memory_sources TEXT NOT NULL DEFAULT '[]'
  CHECK (json_valid(memory_sources) AND json_type(memory_sources) = 'array');

-- Memory's session ledger: one row per chat it read. `transcript` names the chat's kept transcript in the held files.
CREATE TABLE relay_memory_sessions (
  id TEXT PRIMARY KEY,
  owner_subject TEXT,
  device_id TEXT,
  author TEXT,
  agent TEXT,
  host TEXT,
  branch TEXT,
  cwd TEXT,
  started_at TEXT,
  ended_at TEXT,
  status TEXT NOT NULL,
  reason TEXT,
  read_through TEXT,
  raw_bytes INTEGER,
  transcript TEXT,
  updated_at TEXT NOT NULL
);

-- Memory's runs: a capture, a tidy, a daily run or an import. A daily run is one row per owner and day.
CREATE TABLE relay_memory_runs (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  owner_subject TEXT,
  kind TEXT NOT NULL,
  host TEXT,
  day TEXT,
  started_at TEXT,
  finished_at TEXT,
  status TEXT NOT NULL,
  reason TEXT,
  counts TEXT NOT NULL DEFAULT '{}',
  UNIQUE (owner_subject, kind, day)
);

-- What a topic means, and the topic it is another name for: added only, and the newest row for a tag wins.
CREATE TABLE relay_topic_defs (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  tag TEXT NOT NULL,
  definition TEXT,
  alias_of TEXT,
  device_id TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX relay_topic_defs_tag ON relay_topic_defs(tag, seq);

-- The kind column's note names memory's five kinds. An older kind keeps its word and reads as its new kind.
UPDATE relay_memory_columns SET note = 'The kind of fact, as FORMAT.md lists them: user, feedback, project, reference or thread.'
  WHERE name = 'kind';
