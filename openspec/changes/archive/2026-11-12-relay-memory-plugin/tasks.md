# Tasks

## 1. Before the build

- [x] 1.1 Confirm *Update to WongStack 55.2.1* is on `main` and this branch has caught up: `.agents/skills/memory/store/interface.mjs`, `store/contract.mjs`, `scripts/lib/store.mjs` (`WONG_MEMORY_PROFILE`) and `.claude/skills/memory/` are here. Compare `OPERATIONS` and `interface.d.mts` with design §3 and the folder list with §6; update the design where they differ. Stop and return to Matthew if a part in design §7's table is missing.

## 2. The memory store: schema and operations

- [x] 2.1 Write `schema/space-migrations/0019_memory_store.sql` (design §3; the next free number if `0019` is taken) and add it to `MIGRATIONS` in `app/worker/spaces-worker.ts`; backfill `n` by `created_at, id` and `owner_subject` with the person's id. Extend `space-schema.test.ts` and `memory-schema.test.ts`: a space at `0018` with facts migrates, every `n` is unique, and no fact's words change.
- [x] 2.2 Change the `kind` column's note, `schema/knowledge/FORMAT.md` and `plugin/build/FORMAT.md` to the five kinds, and add the old-to-new map (design §4) in `memory.ts`; test that a new fact with an old kind is refused through the store and that an `open` fact reads as `thread`.
- [x] 2.3 Write `app/worker/relay-memory/store.ts`: `relayStore(space, caller)` answering all twelve operations as in design §3, with the role table, `memory_sources` and the `relay:` source, tags, ids, `restate`/`close`, the daily claim, and transcripts in the held files at `memory/transcripts/<session id>`; every SQL statement in this file, `relay-memory/import.ts` or `memory.ts`. Test each operation in `relay-memory/store.test.ts` against a test space.
- [x] 2.4 Run `checkStore(makeStore)` from `.agents/skills/memory/store/contract.mjs` against `relayStore` in `relay-memory/store.test.ts`, plus Relay's cases: a replaced fact stays readable, no `relay_notes`/`relay_health`/`relay_locations` row changes, `transcript` gives the kept bytes, else the saved chat, else `missing`, and an account delete removes the transcripts.

## 3. The memory store: routes and keys

- [x] 3.1 Route `/v1/memory/v2/*` on the connector Worker to `serve(request, { prefix: '/v1/memory/v2/', caller, store })`; only for the `agent` reach, in the connector (`relay-mcp/index.ts`; this repo has no `key-rules.ts`). Test in `relay-mcp/memory-routes.test.ts`, through `httpStore` with `url: <api>/memory`: a computer key gets answers, an API key, the connector and a phone key get 403 and `httpStore` reads it as a refused sign-in, and another person's key never reads this space.
- [x] 3.2 Mark a chat `memory: true` in `GET /v1/chats` when its memory session row is captured, or a fact names its session (design §6). Test in `chats.test.ts`.
- [x] 3.3 Write `app/worker/relay-memory/import.ts` and its routes, `POST /v1/memory/import` and `POST /v1/memory/import/transcript` (design §10), on the `agent` reach only. Test in `relay-memory/import.test.ts`: start refused once memory used the space; the space's own facts move above `highest`; numbers, dates, authors, owners, kinds, tags and sources kept; a resent chunk stores once; a later run after memory used the space adds only new facts, with a new number when the old one is taken; the finish links each replaced fact by old number, fails on a missing number, and answers counts by kind; an imported fact's transcript reads back.
- [x] 3.4 Run `npm run relay:api-doc` in `app/`; update the site's memory page (`site/src/content/docs/api/knowledge-web.md`) for the store route, the import and the five kinds; update `wiki/stack/relay-knowledge-web.md` (the store, `0019`, the kinds map, transcripts, and the import).

## 4. The import script

- [x] 4.1 Write `scripts/import-wongstack-memory.mjs` (design §10): it reads a WongStack checkout's memory only through that checkout's `openStore` and the `--profile` it is given, with read requests only, writes with this computer's Relay Everything key, and `--dry-run` counts only. Test in `scripts/import-wongstack-memory.test.mjs` with a stand-in source that refuses writes and a fake server: every fact, session, tag and transcript arrives; nothing is written to the source; a second run adds only the source's new facts, with links remapped; the counts match the source's `stats`. Add a short *Move a WongStack memory in* part to `wiki/stack/relay-knowledge-web.md`.

## 5. Relay Everything's plugin

- [x] 5.1 Write `scripts/copy-plugin-memory.mjs` (design §6: the folder minus the short list, the skill with the plugin's script path) and run it to make `plugin/memory/` and `plugin/skills/memory/`. Write `plugin/test/memory-copy.test.mjs`: it fails when the copy differs from the source, or a copied file imports one that was not copied. Add the script to the plugin release steps in `wiki/stack/relay-chats.md`.
- [x] 5.2 Write `plugin/memory-profile.mjs` (design §6): `connect` (an `unconfigured` error when memory is off, not connected, saving off, or the repo has its own memory), `topics` from the knowledge copy with repo-relative pages, and `lookup.after` for notes and chats on a topic. Test in `plugin/test/memory.test.mjs` with `fake.mjs`: each part and each no-store case; a failed lookup adds nothing; a topic's page reads at `join(root, page)`.
- [x] 5.3 Add the setup choice to `plugin/bin/connect.mjs` (`memory` kept in `computer.json`, an older file reads as off) and `/relay:memory on|off` as a skill. Test in `connect.test.mjs`: yes, no, and an older file.
- [x] 5.4 Change `plugin/bin/hook.mjs` and `hooks/hooks.json` to the three cases in design §6 (repo memory, memory on, memory off), with `WONG_MEMORY_PROFILE` set for the copy's scripts, memory's daily tidy turned off in the copy's `daily.json` before its session start, no chat saving or build under `WONG_MEMORY_RUN=1`, `PreToolUse` added and `SessionEnd` at 8 seconds. Test in `hook.test.mjs`: each case runs the right scripts, a topic is added once, chat saving runs in all three, the copy starts no daily tidy, and each hook ends within its timeout.
- [x] 5.5 Make `build.mjs work` leave out chats marked `memory: true`, and the build's prompts write the five kinds. Test in `build.test.mjs`.
- [x] 5.6 With memory on, `relay.mjs topic` runs the copy's `pull`. Update `skills/ask`, the skill tests, `plugin/README.md` (the memory choice, what memory saves and where, that a repo's own memory wins, one daily job), the site's Claude Code and Codex pages, and version `0.6.0` in `plugin/.claude-plugin/plugin.json`.

## 6. Checks

- [x] 6.1 Run `npm test` in `app/`, `node --test plugin/test/ scripts/import-wongstack-memory.test.mjs`, `node scripts/product-name.test.mjs`, `node scripts/public-check.mjs`, and `openspec validate relay-memory-plugin --strict --no-interactive`.
- [x] 6.2 In a scratch Claude Code config, install `relay@relay` from this checkout: `claude plugin list` shows one plugin. With memory on, in a scratch repo with no memory, a chat start prints memory's summary from the local stand-in person's space; in a WongStack checkout, it prints only the repo's summary. Repeat the scratch-repo check in Codex.
- [x] 6.3 Locally, point a scratch WongStack checkout's profile at the local server with a computer key: `memory.mjs` saves, searches, pulls and shows a fact's transcript; then import a scratch WongStack store into an empty local space and read one imported fact by its old number with its transcript.
- [x] 6.4 `/save`, then on staging with a key made on this computer ([on this computer](../../../wiki/stack/relay-ai-connector.md#on-this-computer)): with memory on, the plugin saves, replaces and searches a fact; a phone key is refused.
