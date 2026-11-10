# Design

## Context

- **WongStack's memory change** (planned as `modular-memory-plugin`, `/root/.paseo/worktrees/2b9tffs3/modular-memory-plugin/openspec/changes/modular-memory-plugin/`; its shape is under review after Matthew's choice here). What this plan relies on from it: the client calls 12 named operations (`caller`, `facts`, `digest`, `write`, `tags`, `defineTag`, `session`, `putSession`, `transcript`, `putTranscript`, `putRun`, `stats`) and never builds SQL; a remote store answers `POST <url>/v2/<op>` through `serve(request, { prefix, caller, store })`; the client loads one settings module (the *profile*: `connect`, `topics`, `lookup`, `sessionStart`, and optional others) from the repo or `WONG_MEMORY_PROFILE`; and `store/contract.mjs` is the check every backend runs. Today five client files write SQL, so an adapter without this seam would have to rewrite them at each sync.
- **Relay Everything already has memory in each space** ([knowledge web](../../../wiki/stack/relay-knowledge-web.md)): `relay_memory` (add-only facts, `f…` ids, person columns as JSON `fields`, starting with `kind` and `text`, at least one source and one tag), `relay_memory_tags`, `relay_memory_columns`, `relay_note_tags`, and `relay_tag_changes`, all written only by `app/worker/apps/relay/memory.ts`.
- **A space is one Durable Object** (`Space` in `app/worker/spaces-worker.ts`) with one SQLite database. Only `apps/relay/space.ts` opens it, by RPC (`query`, `batch`). The spec today says no caller makes a table or sends a database command.
- **Relay's plugin** (`plugin/`, `relay@relay`) already saves chats (`relay_chats` keyed by device and the app's session id), shows topics at chat start and per message from the local knowledge copy, and has `relay.mjs topic`, `around`, and `points`.
- **Why no plugin dependency (checked 2026-11-10):** Claude Code 2.1.310 installs a plugin's `dependencies` from another shop only when that shop is already added and the root shop allows it; Codex 0.159.2 ignores `dependencies`. Matthew found a two-plugin setup too complicated and chose one chain instead: WongStack → this repo (a WongStack install, by `/wong-sync`) → the public plugin (by a copy at release).

## Goals / Non-Goals

**Goals:** the space answers all 12 operations from `relay_memory` with the same add-only history and passes `store/contract.mjs`; one `relay@relay` install carries memory, off until the person says yes; Relay's plugin owns notes, health, places, and *around a moment*, and feeds memory its topics and pulls.

**Non-Goals:** editing WongStack from here; a plugin architecture, shop, or manifests for memory in WongStack; a dependency between plugins; a generic memory platform or adapters (ruled out 2026-11-05); memory for API keys, the AI connector, or phones; a schedule for memory's background runs; sending agent tables to webhooks; a screen for agent tables.

## Decisions

### 1. The parts

```text
Claude Code / Codex on a computer
  relay@relay (one plugin)
    chat saving, notes, health, places, around, db     always (db: relay-agent-database)
    memory/   copy of this repo's synced WongStack memory client   only when on (§6)
    memory-profile.mjs   Relay's profile for the copy
        │ computer key (agent reach)
        ▼
connector Worker  /v1/memory/v2/<op>  → memory-store.ts → Space (relay_memory…)
```

`memory-store.ts` imports `serve` from the synced memory's interface file in this repo (the path WongStack ships; task 1.1 records it), the same source the plugin's copy is made from, so the client and the server always match.

### 2. The store: route and caller

- **Route:** `/v1/memory/v2/<op>` on the connector Worker, the same `/v1/` the plugin already calls (`computer.api`). `serve({ prefix: '/v1/memory', caller, store: relayStore(space, caller) })`.
- **Caller:** only a computer key (`agent` reach) passes; `key-rules.ts` adds the route to that reach alone. `caller` answers `{ role: 'admin', subject: <personId>, email }`: the space holds one person, so they see all of it, and `everyone` changes nothing. An API key, the connector, and a phone key get 403 before `serve` runs. Visibility is this check plus the space: a key reaches only its own person's space, as today.
- **Every SQL statement is written in `memory-store.ts`**; no operation takes SQL, a table name, or an owner.

### 3. The twelve operations

Migration `0017_memory_store.sql` adds what the operations need and changes no existing row's words:

```sql
ALTER TABLE relay_memory ADD COLUMN n INTEGER;          -- the plugin's number id; backfilled by created_at, id
CREATE UNIQUE INDEX relay_memory_n ON relay_memory(n);
ALTER TABLE relay_memory ADD COLUMN session_id TEXT;    -- the app session the fact came from, set by the server
ALTER TABLE relay_memory ADD COLUMN slug TEXT;          -- the plugin's change or conversation slug
CREATE TABLE relay_memory_sessions (device_id, id, agent, branch, cwd, started_at, ended_at, status, reason,
  read_through, raw_bytes, PRIMARY KEY (device_id, id));             -- the plugin's session ledger
CREATE TABLE relay_memory_runs (seq INTEGER PRIMARY KEY AUTOINCREMENT, device_id, kind, host, started_at,
  status, reason, counts);                                           -- add-only
CREATE TABLE relay_topic_defs (seq INTEGER PRIMARY KEY AUTOINCREMENT, tag, definition, alias_of, device_id,
  created_at);                                                       -- add-only: the newest row per tag wins
```

| Operation | Answered from the space |
|---|---|
| `caller` | the verified key (§2) |
| `facts` | one SQL read per query on `relay_memory` + tags: `ids` → `n`; `terms` → each word `LIKE` in `text` (as `factPage` does); `tags` → `tagged()` with aliases from `relay_topic_defs`; `type`/`notType` → `kind` (§4); `slug`, `since`/`until`, `author` (device name); `branch`/`change` → the session's branch or `slug`; `all` → replaced too; `order` `rank` reads as newest; `limit` capped at 200. Each row maps to the plugin's `Fact`: `id=n`, `body=fields.text`, `type`, `superseded_by` = the replacer's `n`, `owner_subject=personId`, `shared=0`, `sources`, `tags`. |
| `digest` | one `batch`: live facts newest first to `limit`, live threads counted by step tag, live facts on the `slug`, the last run, and the last `dream` run for the consolidation clock. |
| `write` | one `batch`, all or none, through `memory.ts`'s checks. A new fact → a row with `fields { kind: type, text: body }`, its tags, `replaces` from `supersedes` (by `n`), `session_id` and `slug` from the request. `restate` → `changeTags` add on that fact, kept in `relay_tag_changes`: words, date, and device unchanged. `close` → a new `thread` fact with the thread's tags that replaces it. `left` is always empty: one person owns every fact. |
| `tags` | the tags in `relay_memory_tags` and `relay_note_tags`, with uses, and each tag's newest `relay_topic_defs` row. |
| `defineTag` | adds a `relay_topic_defs` row. |
| `session`, `putSession` | `relay_memory_sessions` for this device: an upsert, as WongStack's ledger is. |
| `transcript` | the fact's `relay:chat/<id>` source → that chat's messages from `relay_chat_messages`, as bytes; no chat → `{ missing: 'the chat was not saved' }`. |
| `putTranscript` | answered `{}` and stores nothing: the chat is the transcript, and Relay's own hooks already send it (Decision log). |
| `putRun` | adds a `relay_memory_runs` row. |
| `stats` | counts by kind, live and replaced, sessions, runs, and the last consolidation. |

- **Same history rule.** No operation edits words or deletes a fact. A replace sets `replaced_by` in the same batch, the one change a fact gets, as `memory.ts` does now. `n` and `session_id`, `slug` are set once, at insert.
- **Sources.** A write's source names its own session only; the server turns it into `relay:chat/<chat id>` when that device has a chat with that session id, else `relay:day/<YYYY-MM-DD>` of the fact's time, so the space's "at least one source" rule holds. A write may also name existing `relay:note|chat|day|…` links; a link to a record not in the space is refused. Reads return `relay:` links; the plugin prints them.
- **Tags.** The space needs one tag per fact. A write with none takes its `slug` as the tag; with no slug it is refused with the reason, and the plugin's spool keeps it.
- **Ids.** A new fact's `n` is `max(n) + 1` inside the batch, which a Durable Object runs alone. `relay:fact/<id>` links keep the `f…` id.
- **The check.** `memory-store.test.ts` runs WongStack's `checkStore(makeStore)` against a test space, plus Relay's own cases: history kept, a sync table untouched, a non-computer key refused.

### 4. Kinds

`relay_memory_columns.kind`'s note and `schema/knowledge/FORMAT.md` list the plugin's five: `user`, `feedback`, `project`, `reference`, `thread`. A write checks `kind` against them. A read maps an older value without changing the row: `open` → `thread`, `preference` → `feedback`, `fact`/`decision`/`plan` → `project`, `reference` → `reference`. A `type` filter matches both the new kind and the old kinds that map to it. The `/v1/memory` reads return the stored word, as today.

### 5. The agents' database

Moved to its own change, `relay-agent-database`, which ships first. Memory never uses it.

### 6. Memory inside Relay's plugin

- **The adapter.** `scripts/copy-plugin-memory.mjs` copies memory's client from this repo's synced WongStack files to `plugin/memory/`, by a short list in the script: the CLI, the three hook scripts, their `lib/`, and the interface with its HTTP client. It leaves out WongStack's own database code (the D1 store, sign-in, admin jobs, migrations, the Worker), tests, and `store/contract.mjs`. It writes memory's skill to `plugin/skills/memory/SKILL.md` with the plugin's script path. The plugin release runs it; `plugin/test/memory-copy.test.mjs` fails when the copy differs from the source, or when a copied file imports a file that was not copied, so a `/wong-sync` that changes memory updates the copy in the same change. The copy is MIT code from Matthew's own public repo, so `public-check.mjs` passes it.
- **Relay's settings.** `plugin/memory-profile.mjs`, no packages, as the rest of `plugin/`. `hook.mjs` and the memory skill set `WONG_MEMORY_PROFILE` to it for each memory script they run:
  - `connect`: reads `computer.json`; returns `{ url: computer.api + '/memory', headers: () => ({ Authorization: 'Bearer ' + key }) }`. Memory off, no connection, saving off in this project (`saving.mjs`'s rule), or a repo with its own memory (§8) → no store, and the copy stays quiet.
  - `topics`: the local knowledge copy's pages, as `relay.mjs` reads them today, each `{ tag, kind: 'company', page, summary }`.
  - `lookup(ctx, topic)`: the notes with that tag and the titles and summaries of up to 3 chats its facts came from, through `/v1/`; a failure adds nothing.
  - `sessionStart`: the knowledge sync the hook runs today (at most every 15 minutes, detached).
  - No `steps`, `currentSlug`, `slugState`, or `person`.
- **The setup choice.** After the sign-in, `/relay:connect` asks *Also remember things for you?* and keeps `memory: true|false` in `computer.json`; `/relay:memory on|off` changes it later. A computer connected before this release reads as off.
- **Hooks.** `hooks.json` keeps `SessionStart`, `UserPromptSubmit`, `Stop`, and `SessionEnd`, and adds `PreToolUse` on edit tools. `hook.mjs` decides each time:
  - repo with its own memory (§8) → chat saving only; no topics, no memory;
  - memory on → the copy's `session-start.mjs`, `topic-match.mjs`, and `before-edit.mjs`, within their timeouts (5, 3, 3 seconds), in place of Relay's own topic lines and match;
  - memory off → Relay's own topic lines and match, as today, and `PreToolUse` exits at once.
  Chat saving runs in every case.
- **Skills.** `skills/memory` (the copy's) says to turn memory on with `/relay:memory on` when it is off. `ask` keeps `topic`, `around`, `points`, and `db`; with memory on, `relay.mjs topic` calls the copy's topic pull so the answer is one.

### 7. What this needs from WongStack

Sent to WongStack's memory chat on 2026-11-10 for Matthew to decide there; nothing is edited from here:

- **Needed:** named requests (the 12 operations, the HTTP client, `serve`), with no SQL in a client file; one settings module loaded from the repo or `WONG_MEMORY_PROFILE`; WongStack's own database code in files a short list can leave out; `store/contract.mjs`; `sources` on facts; topics.
- **Not needed:** a plugins folder, plugin manifests, plugin hook files, a shop, a Codex plugin install, or a setup guide for other repos. WongStack's hooks can stay in its settings.

Task 1.1 reads what WongStack shipped and stops for Matthew if a needed part is missing.

### 8. Repos that have their own memory

The copy stays off where the repo has memory: the repo holds WongStack's memory (`.agents/skills/memory/` or `.agents/memory/profile.mjs`), or `WONG_MEMORY_PROFILE` is already set when the hook starts. A WongStack install (WongOS, this repo) therefore runs only its own memory, once. Relay's plugin still saves chats and answers notes, health, places, and *around a moment* there. A repo that wants its facts in a person's space writes its own profile.

## Risks / Trade-offs

- [WongStack's interface changes before it ships] → this build waits for `modular-memory-plugin` on WongStack's `main` and its sync here; the first task reads the shipped `interface.mjs` and updates §3's table if it differs.
- [WongStack ships a different shape] → task 1.1 reads it first; §3's table and the adapter's list follow what shipped.
- [The copy goes stale] → the copy test fails on any difference, so the change that syncs WongStack updates it.
- [The copy's hooks are slower inside Relay's hook] → `hook.mjs` runs them with their own timeouts and prints what finished; a late part prints nothing, as memory does today.
- [Two memories in one chat] → §8; the build checks a WongStack install with `relay@relay` and memory on shows one summary, the repo's.
- [`LIKE` search is slower than FTS] → a person's facts number in the thousands; FTS can come later behind the same `facts` operation.
- [Old kinds read differently than they were written] → the mapping is fixed in §4 and reads only; no row changes.

## Migration Plan

1. WongStack ships its memory change with the parts in §7; `/wong-sync` brings it here.
2. Publish the server: migration `0017` runs in each space on first use, in [the Workers' order](../../../wiki/relay-spaces.md#the-workers-and-their-order).
3. Release the plugin `0.5.0` with the copy. Each computer keeps working with memory off; `/relay:connect` or `/relay:memory on` turns it on.
4. Rollback: revert the release. `0017` only adds columns and tables; old code ignores them.

## Open Questions

None.
