# Design

## Context

- **WongStack 55.2.1** (commit `a282a4a9`; read in `/root/.cache/wong-stack/WongStack`) ships the memory this plan waited for. The chat *Update to WongStack 55.2.1* syncs it here. What this plan uses from it:
  - **The plugin folder** `.agents/skills/memory/` in this repo (WongStack's own layout names it `.agents/plugins/memory/`), self-contained: `README.md`, `scripts/` (the CLI `memory.mjs`, the hook scripts `session-start.mjs`, `topic-match.mjs`, `before-edit.mjs`, `session-end.mjs`, the background `run.mjs`, and `lib/`), `store/interface.mjs` (the 12 `OPERATIONS`, `httpStore`, `serve`, `StoreError`), `store/interface.d.mts` (the `Fact`, `FactQuery`, `FactWrite`, `RunWrite` and `Digest` shapes), `store/contract.mjs` (`checkStore(makeStore)`), `skills/dream-memory/`, `hooks/` (`claude.json`, `codex.json`), `.claude-plugin/`, `.codex-plugin/`, `references/`, and `SKILL.md`. The agents read it at `.claude/skills/memory/`, an untracked copy of the same files.
  - **The profile**: `scripts/lib/store.mjs` loads `WONG_MEMORY_PROFILE`, else `<repo>/.agents/memory/profile.mjs`. Its parts: `connect` (a store, or `{ url, headers }` for the plugin's own `httpStore`), `topics`, `steps`, `currentSlug`, `slugState`, `person`, `lookup` (`{ named, before, after, files }`), `tidy` (`{ pages, deny, publish }`), `sessionStart`, `commands`. Each is optional except `connect`.
  - **WongStack's own parts** sit outside the plugin, in `.agents/memory/` (the D1 store, sign-in, migrations, admin jobs, the profile). The app's memory route is `/_memory/v2/`.
  - **New since this plan was written**: the daily tidy and `pull`/`related` (53.0.0), memory sending each chat's redacted transcript itself (52.0.0), and the files behind each fact through `lookup.files` (55.1.0).
- **Relay Everything already has memory in each space** ([knowledge web](../../../wiki/stack/relay-knowledge-web.md)): `relay_memory` (add-only facts, `f…` ids, person columns as JSON `fields`, starting with `kind` and `text`, at least one `relay:` source, a device and a `client_id`), `relay_memory_tags`, `relay_memory_columns`, `relay_note_tags`, and `relay_tag_changes`, all written only by `app/worker/apps/relay/memory.ts`. Migrations `0017_note_places` and `0018_note_pins` shipped since this plan; the next free number is `0019`.
- **A space is one Durable Object** (`Space` in `app/worker/spaces-worker.ts`) with one SQLite database. Only `apps/relay/space.ts` opens it, by RPC (`query`, `batch`), and gives each request the person's held files in `RELAY_BUCKET` (`files.put`, `get`, `removeAll`), which the account delete empties.
- **Relay's plugin, version 0.5.1** (`plugin/`, `relay@relay`): saves chats (`relay_chats`, keyed by device and the app's session id); shows topics at chat start and per message from the local knowledge copy; has `relay.mjs topic`, `around`, `points`, and `db` (the agents' database, `relay-agent-database`, shipped in 0.5.1); and runs the daily build, `build.mjs run`, which reads chats and notes into facts and topics and gardens the web's pages in Cloudflare Artifacts.
- **WongOS** runs WongStack 51.10, before memory became a plugin: 2,067 facts (1,124 live, highest id 2067), 469 sessions, one author, 1,969 facts owned by Matthew's WongOS sign-in and 31 team facts with no owner. Its side of the move is the plan *Relay Everything in WongOS* (branch `nifty-goat` in `/root/WongOS`), which first updates WongOS to WongStack 55.2.1.
- **Why no plugin dependency (checked 2026-11-10):** Claude Code 2.1.310 installs a plugin's `dependencies` from another shop only when that shop is already added and the root shop allows it; Codex 0.159.2 ignores `dependencies`. Matthew chose one chain instead: WongStack → this repo (a WongStack install, by `/wong-sync`) → the public plugin (by a copy at release).

## Goals / Non-Goals

**Goals:** the space answers all 12 operations from `relay_memory` with the same add-only history and passes `store/contract.mjs`; a full WongStack project's memory works on it with a computer key; WongOS's memory moves in once, keeping numbers, dates, authors, kinds, topics, sources, replace links and transcripts; one `relay@relay` install carries memory, off until the person says yes; Relay's plugin owns notes, health, places, and *around a moment*, and feeds memory its topics and pulls.

**Non-Goals:** editing WongStack from here; WongOS's own switch (its plan); a plugin architecture or a dependency between plugins; a generic memory platform (ruled out 2026-11-05); memory for API keys, the AI connector, or phones; teams or shared spaces in Relay Everything; sending memory tables to webhooks; a screen for sessions or transcripts.

## Decisions

### 1. The parts

```text
Claude Code / Codex on a computer
  relay@relay (one plugin)
    chat saving, notes, health, places, around, db, daily build     always
    memory/   copy of this repo's synced .agents/skills/memory/      only when on (§6)
    memory-profile.mjs   Relay's profile for the copy
        │ computer key (agent reach)
        ▼
  WongOS (a WongStack project)
    .claude/skills/memory/ + .agents/memory/profile.mjs → connect: { url: <relay>/v1/memory, key }   (§9)
        │ computer key (agent reach)
        ▼
connector Worker  /v1/memory/v2/<op>  → relay-memory/store.ts → Space (relay_memory…) + held files (transcripts)
                  /v1/memory/import…  → relay-memory/import.ts (§10)
```

`relay-memory/store.ts` imports `serve`, `OPERATIONS` and `StoreError` from `.agents/skills/memory/store/interface.mjs` in this repo, the same source the plugin's copy is made from, so the client and the server always match.

### 2. The store: route and caller

- **Route:** `/v1/memory/v2/<op>` on the connector Worker, the same `/v1/` the plugin calls (`computer.api`). The client's `url` is `<api>/memory`; `httpStore` adds `/v2/<op>`, so the server calls `serve(request, { prefix: '/v1/memory/v2/', caller, store: relayStore(space, caller) })`.
- **Caller:** only a computer key (`agent` reach) passes: the connector (`relay-mcp/index.ts`, through `relay-mcp/memory-routes.ts`) answers `/v1/memory/v2/` and `/v1/memory/import` before `/v1/`'s own routes, and only for a key whose asker is a computer, as `answers.ts`'s `computer()` does for facts. This repo has no `key-rules.ts`. `caller` answers `{ role: 'admin', subject: <personId>, email: <account email> }`. An API key, the connector and a phone key get 403 before `serve` runs; `httpStore` reads a 403 with no store `kind` as a refused sign-in. A key reaches only its own person's space, as today.
- **Every SQL statement is written in `relay-memory/store.ts`, `relay-memory/import.ts` or `memory.ts`**; no operation takes SQL, a table name, or an owner.

### 3. The twelve operations

Migration `0019_memory_store.sql` adds what the operations need and changes no existing row's words:

```sql
ALTER TABLE relay_memory ADD COLUMN n INTEGER;            -- memory's number id; backfilled by created_at, id
CREATE UNIQUE INDEX relay_memory_n ON relay_memory(n);
ALTER TABLE relay_memory ADD COLUMN slug TEXT;            -- memory's change or conversation slug
ALTER TABLE relay_memory ADD COLUMN session_id TEXT;      -- memory's session, such as claude:<uuid>
ALTER TABLE relay_memory ADD COLUMN author TEXT;          -- an email; null for Relay's own build facts
ALTER TABLE relay_memory ADD COLUMN owner_subject TEXT;   -- the person's id; null for a team fact
ALTER TABLE relay_memory ADD COLUMN shared INTEGER NOT NULL DEFAULT 1;
ALTER TABLE relay_memory ADD COLUMN memory_sources TEXT NOT NULL DEFAULT '[]';  -- memory's own sources, as written
CREATE TABLE relay_memory_sessions (id PRIMARY KEY, owner_subject, device_id, agent, host, branch, cwd,
  started_at, ended_at, status, reason, read_through, raw_bytes, transcript);   -- the session ledger
CREATE TABLE relay_memory_runs (seq INTEGER PRIMARY KEY AUTOINCREMENT, owner_subject, kind, host, day,
  started_at, status, reason, counts, UNIQUE (owner_subject, kind, day));     -- day set only for `daily`
CREATE TABLE relay_topic_defs (seq INTEGER PRIMARY KEY AUTOINCREMENT, tag, definition, alias_of, device_id,
  created_at);                                                                -- add-only: the newest row per tag wins
```

The build backfills `owner_subject` with the person's id. The shapes are `store/interface.d.mts`'s.

| Operation | Answered from the space |
|---|---|
| `caller` | the verified key (§2) |
| `facts` | `FactQuery[]` → `Fact[][]`, one SQL read per query on `relay_memory` + tags, with the caller's visibility (below): `ids` → `n`; `terms` → each word `LIKE` in `text`; `tags` → `tagged()` with aliases from `relay_topic_defs`; `type`/`notType` → `kind` (§4); `slug`/`notSlug`, `session`, `since`/`until`, `author`; `branch`/`change` → the session's branch or `slug`; `all` → replaced too; `everyone`; `order` `rank` reads as newest, `threads-first`; `withTags`; `limit` capped at 200. A row maps to `Fact`: `id=n`, `slug`, `type` (§4), `body=fields.text`, `author`, `created_at` (ISO), `session_id`, `superseded_by` = the replacer's `n`, `owner_subject`, `shared`, `sources=memory_sources`, `tags`. |
| `digest` | one `batch`: `live`, `threads` on the `slug` and `steps` by step tag, the caller's last `run`, the last `daily` run, `lately` (tags of the last 7 days, 8 at most), and `fresh` (the caller's own `feedback`/`user` facts since the last finished daily run, or 24 hours; 5 at most). |
| `write` | one `batch`, all or none, through `memory.ts`'s checks. `session` upserts the session row; `newTags` adds `relay_topic_defs` rows for tags not yet defined. A new fact → a row with `fields { kind: type, text: body }`, `n = max(n) + 1`, its tags, `replaces` from `supersedes` (by `n`), `slug`, `session_id`, `author` and `owner_subject` from the caller, `shared` by the role table, `memory_sources` as written, `created_at` from `createdAt` or now, and a `relay:` source (below). `restate` → a new fact with the old one's words, `created_at`, author, sources and its tags plus the new ones, which replaces it. `close` → a new `project` fact with the thread's tags that replaces it. A supersede the role table refuses leaves the fact live and names it in `left`. |
| `tags` | each tag in `relay_memory_tags` and `relay_note_tags`, with uses, and its newest `relay_topic_defs` row. |
| `defineTag` | admin only; adds a `relay_topic_defs` row. |
| `session`, `putSession` | `relay_memory_sessions`: the owner's own row, or any row for an admin. A `private` session stays private. |
| `transcript` | the fact's session → its kept transcript from the held files; else the device's saved chat with that session id, as text; else `{ missing, session }`; no such fact → `{ fact: null }`. |
| `putTranscript` | the owner's session only; keeps the bytes in the held files at `memory/transcripts/<session id>`, up to `MAX_TRANSCRIPT_BYTES`, and answers `{ key }`. |
| `putRun` | adds a `relay_memory_runs` row. A `daily` `started` claims the day once per owner, or again with `force`, and answers `{ claimed }`; `ok`/`failed` fills that row. A team caller is refused. |
| `stats` | `types` (by kind, live), `totals` (`facts`, `live`, `sessions`, `private`), and `consolidations`. |

- **Same history rule.** No operation edits words or deletes a fact. A replace sets `replaced_by` in the same batch, the one change a fact gets, as `memory.ts` does now. `n`, `slug`, `session_id`, `author`, `owner_subject`, `shared` and `memory_sources` are set once, at insert. The import's one renumbering (§10) is the only exception.
- **Who sees what.** The store follows WongStack's role table as `store/contract.mjs` tests it (`admin`, `member`, `reader`, `team`, and an admin key with no person), by `owner_subject` and `shared`. Every key today is its own person's, so it calls as `admin` with the person's id: it sees its own and team facts, and everything with `everyone`. The table matters for imported team facts and for the store check.
- **Sources.** `memory_sources` holds memory's own sources as written (`session:<id>`, a path, a link), never checked against the space; reads give them back exactly. Relay's `sources` column keeps its rule of at least one `relay:` link: the server sets `relay:chat/<id>` when the device has a chat with that session's id, else `relay:day/<YYYY-MM-DD>` of the fact's time. A `relay:` link in memory's sources is also checked, and one to a record not in the space is refused. The page and the connector show `relay:` sources, as today.
- **Tags.** A store fact may have no tag, as memory allows; `relay_memory_tags` has no rule against it, and the one-tag rule stays for Relay's own `add-facts` and tag changes.
- **Ids.** A new fact's `n` is `max(n) + 1` inside the batch, which a Durable Object runs alone. `relay:fact/<id>` links keep the `f…` id.
- **The check.** `relay-memory/store.test.ts` runs `checkStore(makeStore)` against a test space, where `as(caller)` gives `relayStore(space, caller)`, plus Relay's own cases: history kept, no `relay_notes`/`relay_health`/`relay_locations` row changed, a non-computer key refused.

### 4. Kinds

`relay_memory_columns.kind`'s note, `schema/knowledge/FORMAT.md`, and the daily build's `plugin/build/FORMAT.md` list the five: `user`, `feedback`, `project`, `reference`, `thread`. A write checks `kind` against them. A read through the store maps an older value without changing the row: `open` → `thread`, `preference` → `feedback`, `fact`/`decision`/`plan` → `project`, `reference` → `reference`. A `type` filter matches the new kind and the old kinds that map to it. `GET /v1/memory`'s `kind` filter does the same: `kind=project` also finds `fact`, `decision` and `plan`, and an older word, such as `kind=decision`, finds only itself. The `/v1/memory` reads return the stored word, as today.

### 5. The agents' database

Shipped in its own change, `relay-agent-database` (plugin 0.5.1). Memory never uses it.

### 6. Memory inside Relay's plugin

- **The copy.** `scripts/copy-plugin-memory.mjs` copies `.agents/skills/memory/` to `plugin/memory/`, leaving out a short list: `hooks/`, `.codex-plugin/`, `.claude-plugin/` and `README.md` (Relay's hook runs the scripts, and Relay's plugin has its own README), `skills/dream-memory/` (the daily tidy; below), `references/setup.md` (setup is `/relay:connect`), `scripts/lib/documents/runtime/` (packages; the document search stays off until a host sets it up, and memory reads facts without it), and `store/contract.mjs`. It writes memory's `SKILL.md` to `plugin/skills/memory/SKILL.md` with the plugin's script path; the copy's `pluginPath` already prints full paths outside a WongStack checkout. The plugin release runs it; `plugin/test/memory-copy.test.mjs` fails when the copy differs from the source, or when a copied file imports a file that was not copied, so a `/wong-sync` that changes memory updates the copy in the same change. The copy is MIT code from Matthew's own public repo, so `public-check.mjs` passes it.
- **Relay's profile.** `plugin/memory-profile.mjs`, no packages, as the rest of `plugin/`. `hook.mjs` and the memory skill set `WONG_MEMORY_PROFILE` to it for each memory script they run:
  - `connect`: reads `computer.json`; returns `{ url: computer.api + '/memory', headers: () => ({ Authorization: 'Bearer ' + key }) }`. Memory off, no connection, saving off in this project (`saving.mjs`'s rule), or a repo with its own memory (§8) → it throws `StoreError` of kind `unconfigured`, and the copy stays quiet.
  - `topics`: the local knowledge copy's pages, as `relay.mjs` reads them, each `{ tag, kind: 'company', page, summary, aliases: [], paths: [page], docs: [page] }`. Memory reads a page at `join(ctx.root, page)`, so `page` is the copy's file relative to the repo root.
  - `lookup.after(ctx, { tags })`: for a pulled topic, the notes with its tag and the titles and summaries of up to 3 chats its facts came from, through `/v1/`; a failure adds nothing.
  - No `steps`, `currentSlug`, `slugState`, `person`, `tidy`, `commands`, `sessionStart`, or `lookup.named/before/files`: a side project has no WongStack verbs, and `hook.mjs` already syncs the knowledge copy.
- **One daily job.** Relay's daily build stays the person's one daily job. Before the copy's `session-start.mjs` runs, `hook.mjs` loads `plugin/lib/daily-off.mjs` (`node --import`), which writes `off: true` into the copy's `daily.json` in memory's state folder, by the copy's own `repoContext` and `setDaily`. So the start starts no daily tidy (`dailyBlocker`: *off on this computer*), but still starts the capture of the chats that wait, on its own. No copy script gets `WONG_MEMORY_NO_HEADLESS`: with it, the start would start no capture either, and would ask the open chat to start a subagent for it. The copy's `session-end.mjs` starts each chat's capture when it ends. `hook.mjs` saves no chat and starts no build when `WONG_MEMORY_RUN=1`, as for `RELAY_BUILD_RUN`, so memory's background run is never saved as a chat.
- **The build skips what memory read.** `GET /v1/chats` marks a chat `memory: true` when memory read it: its `relay_memory_sessions` row, `claude:` or `codex:` and the chat's session id, has the status `captured`, or a fact in the space has that session id as `session_id`. A row alone is not enough: memory's chat end writes one (`skipped`, *not captured yet*) before the capture runs. `build.mjs work` leaves those chats out; it still reads notes.
- **The setup choice.** After the sign-in, `/relay:connect` asks *Also remember things for you?* and keeps `memory: true|false` in `computer.json`; `/relay:memory on|off` changes it later. A computer connected before this release reads as off.
- **Hooks.** `hooks.json` keeps `SessionStart`, `UserPromptSubmit`, `Stop`, and `SessionEnd`, adds `PreToolUse` on `Edit|Write|MultiEdit|NotebookEdit`, and gives `SessionEnd` 8 seconds. `hook.mjs` decides each time:
  - repo with its own memory (§8) → chat saving only; no topics, no memory;
  - memory on → the copy's `session-start.mjs`, `topic-match.mjs`, `before-edit.mjs` and `session-end.mjs`, within their timeouts (5, 3, 3, 5 seconds), in place of Relay's own topic lines and match;
  - memory off → Relay's own topic lines and match, as today, and `PreToolUse` exits at once.
  Chat saving and the daily build start run in every case.
- **Skills.** `skills/memory` (the copy's) says to turn memory on with `/relay:memory on` when it is off. `ask` keeps `topic`, `around`, `points`, and `db`; with memory on, `relay.mjs topic` calls the copy's `memory.mjs pull <topic>`, whose answer already holds the profile's notes and chats.

### 7. What this needs from WongStack

Checked against 55.2.1 on 2026-11-12. Every needed part shipped; nothing is edited from here:

| Needed | Shipped |
|---|---|
| Named requests, with no SQL in a client file | `store/interface.mjs` `OPERATIONS`, `httpStore`; the D1 code is in `.agents/memory/d1/` |
| `serve(request, { prefix, caller, store })` | `store/interface.mjs` |
| One settings module from the repo or `WONG_MEMORY_PROFILE` | `scripts/lib/store.mjs` `loadProfile` |
| WongStack's own database code outside a short list | outside the plugin folder, in `.agents/memory/` |
| `store/contract.mjs` | `checkStore(makeStore)`, with a role table and a daily claim |
| `sources` on facts; topics | `Fact.sources`; `profile.topics`, `pull`, `related` |

**Not needed:** a plugins folder of Relay's own, manifests, a shop, or a setup guide for other repos. WongStack's hooks file stays out of the copy.

Task 1.1 confirmed on 2026-11-12 that the sync is live here: `OPERATIONS` lists the same twelve operations as §3, and `interface.d.mts`'s `Fact`, `FactQuery`, `FactWrite`, `RunWrite` and `Digest` match §3. Only the folder's place differs: `.agents/skills/memory/`, not `.agents/plugins/memory/`.

### 8. Repos that have their own memory

The copy stays off where the repo has memory: the repo holds WongStack's memory (`.claude/skills/memory/` or `.agents/memory/profile.mjs`), or `WONG_MEMORY_PROFILE` is already set when the hook starts. A WongStack project (WongOS, this repo) therefore runs only its own memory, once, wherever its profile keeps the facts. Relay's plugin still saves chats and answers notes, health, places, and *around a moment* there.

### 9. A WongStack project on the store

A WongStack project uses the store by its own profile: `.agents/memory/profile.mjs` `connect` returns `{ url: '<your-relay-server>/v1/memory', headers }` with a computer key of the person. The store treats it as any computer key (§2). It needs nothing more from this change:

- It sends `steps`, slugs, `newTags`, sessions and transcripts; the store keeps them all (§3).
- Its daily tidy claims the day by `putRun` in `relay_memory_runs`, apart from Relay's build, which claims its day in the web's `builds.log`. The tidy edits the project's own pages; the build gardens the web. They do different work.
- Its capture writes facts from chats that Relay's plugin also saves (saving is on in WongOS). The build skips a chat whose session memory has a row for (§6). For a chat memory has not read yet, the build's `check-facts` drops a fact the space already holds, so a same fact is nothing new.
- Where the key comes from and how each of WongOS's computers gets one is WongOS's plan.

### 10. The one-time import

The import moves a WongStack memory in, in one main run and, if the source changed meanwhile, one or more catch-up runs. WongOS runs it once before its switch and again right after.

- **The routes**, on the same computer-key reach, routed in `relay-mcp/memory-routes.ts` and answered in `relay-memory/import.ts`. `POST /v1/memory/import` takes one JSON body of four kinds:
  - `{}` → `{ imported, used, highest }`: how many facts came in by import, whether memory used the space (below), and the highest `n`;
  - `{ start: { highest } }` → `{ moved }`;
  - a chunk `{ subject, facts, sessions, tags }` → `{ added, skipped, renumbered: [{ old, new }] }`, where `subject` is the source's id of the importing person, `facts` are the source's `Fact` rows, `sessions` its session rows, and `tags` its `tags` rows;
  - `{ finish: { links: [{ id, by }] } }` → `{ linked, counts: { live, all } }`, each link an imported fact's old number and its replacer's old number, each count by kind.

  `POST /v1/memory/import/transcript?session=<id>` with the bytes → `{ key }`, or `{ skipped: true }` when one is kept.
- **Start**, in the first run only. Refused when the space has a session row, a fact with a `session_id` or `slug`, or an imported fact: memory has used it, and its numbers are in use. Else, in one batch, the space's own facts move to `n` above `highest`, in their order. No one has read those numbers yet, so nothing points at them. A later run sends no `start`.
- **Facts.** Each is keyed by its source number: `client_id` is `import:<old id>`, so a fact already imported is skipped, in any run. A new one keeps its old number as `n` when that number is free, else takes the next free number; the chunk's answer names each `old → new` that differs. It keeps its `slug`, `type` as `kind`, `body`, `author`, `created_at`, `session_id`, `owner_subject` (the source's id of the importing person becomes the space's person id; others stay as they are), `shared`, `sources` as `memory_sources`, and `tags`. Chunks hold up to 200 facts, in number order. In the main run every number is free, so #628 stays #628; only a fact the source added after the main run can get a new number.
- **Finish**, in each run. The script sends every link the source holds, so a later run sends the old ones again. In one batch, each imported fact the source marks superseded gets `replaced_by` its replacer's `f…` id, found by the replacer's old number, and the replacer `replaces` it; a link already set is skipped. A link to a number not imported fails the finish and names it. The finish adds a run row `import` and answers the imported facts' counts, live and in all, by kind, so the source's `stats` can be compared with it. An imported fact counts as live unless an imported fact replaced it: after the switch, a fact memory writes in the space may replace one, such as #628, which the read-only source still holds live. The space's `stats` also counts Relay's own build facts, so it is larger.
- **Sessions, tags and transcripts.** Session rows and tag definitions come with the chunks, each stored once by its id or name. Each transcript goes to `memory/transcripts/<session id>`, as `putTranscript` keeps it, skipped when one is there, so `transcript` works for imported facts.
- **The script.** `scripts/import-wongstack-memory.mjs --from <WongStack checkout> [--profile <file>] [--dry-run]` reads the source only through that checkout's memory plugin (`openStore` from its `.claude/skills/memory/scripts/lib/store.mjs`), with the profile `--profile` names, else the checkout's own, and that profile's sign-in. So after WongOS's profile points at the space, a profile for the old store still reads it. It uses only the read requests (`caller`, `facts` with `all`, `everyone` and `withTags` by number ranges, `tags`, `session`, `transcript`, `stats`), so a source that refuses every write still works. It writes to the space with this computer's Relay Everything key, never to the source, and holds no address. `--dry-run` reads and prints the counts only. A run sends `start` only when the space has no imported fact.
- **The source stays.** WongOS's old store stays as it is, as a read-only backup; *Relay Everything in WongOS* stops its writes and switches WongOS's profile.

## Risks / Trade-offs

- [The WongStack update changes before it is live] → task 1.1 reads the synced files first; §3 and §6 follow what is synced.
- [The copy goes stale] → the copy test fails on any difference, so the change that syncs WongStack updates it.
- [The copy's hooks are slower inside Relay's hook] → `hook.mjs` runs them with their own timeouts; a late part prints nothing, as memory does today.
- [Two memories in one chat] → §8; the build checks that a WongStack checkout with `relay@relay` and memory on shows one summary, the repo's.
- [Two jobs save the same chat's facts] → the build skips chats memory read (§6).
- [Topic page paths read oddly] → memory prints each page relative to the repo root, such as `../../.config/relay-everything/knowledge/topics/battery.md`. If that confuses, ask WongStack to read an absolute page as is.
- [`LIKE` search is slower than WongStack's stemmed search] → a person's facts number in the thousands (WongOS: 2,067); full-text search can come later behind the same `facts` operation.
- [Old kinds read differently than they were written] → the mapping is fixed in §4 and reads only; no row changes.
- [An import stops half way] → each chunk is all or none and a fact already imported is skipped, so the script runs again from the start. WongOS's switch waits for the finish.
- [Transcripts cost storage] → each is at most 50 MB, kept in the person's held files, and deleted with the account.

## Migration Plan

1. *Update to WongStack 55.2.1* is live; this branch catches up with `main`.
2. Publish the server: migration `0019` runs in each space on first use, in [the Workers' order](../../../wiki/relay-spaces.md#the-workers-and-their-order).
3. Release the plugin `0.6.0` with the copy. Each computer keeps working with memory off; `/relay:connect` or `/relay:memory on` turns it on.
4. *Relay Everything in WongOS* updates WongOS, stops writes to its old store, runs the import, and switches its profile to the store.
5. Rollback: revert the release. `0019` only adds columns and tables; old code ignores them. WongOS switches its profile back to its old store, which kept every fact up to the import.

## Open Questions

None.
