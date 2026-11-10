# Tasks

## 1. Before the build

- [ ] 1.1 Confirm WongStack's memory change is on WongStack's `main` and synced here by `/wong-sync`: the client calls named operations with no SQL, `serve` and `store/contract.mjs` exist, and the settings module loads from `WONG_MEMORY_PROFILE`. Record the shipped paths in design §1 and §6, and update §3's table where the shipped `OPERATIONS` and `Fact` types differ. Stop and return to Matthew if a part design §7 needs is missing.

## 2. The memory store: schema and operations

- [ ] 2.1 Write `schema/space-migrations/0017_memory_store.sql` (design §3) and add it to `MIGRATIONS` in `app/worker/spaces-worker.ts`; backfill `n` by `created_at, id`. Extend `space-schema.test.ts` and `memory-schema.test.ts`: a space at `0016` with facts migrates, every `n` is unique, and no fact's words change.
- [ ] 2.2 Change the `kind` column's note and `schema/knowledge/FORMAT.md` to the five kinds, and the old-to-new map (design §4) in `memory.ts`; test that a new fact with an old kind is refused through the store and that an `open` fact reads as `thread`.
- [ ] 2.3 Write `app/worker/apps/relay/memory-store.ts`: `relayStore(space, caller)` answering all twelve operations as in design §3, with sources, tags, ids and `restate`/`close` rules; every SQL statement in this file or `memory.ts`. Test each operation in `memory-store.test.ts` against a test space.
- [ ] 2.4 Run WongStack's `checkStore(makeStore)` from `store/contract.mjs` against `relayStore` in `memory-store.test.ts`, plus Relay's cases: a replaced fact stays readable, no `relay_notes`/`relay_health`/`relay_locations` row changes, `transcript` returns the saved chat or `missing`, `putTranscript` stores nothing.

## 3. The memory store: route and keys

- [ ] 3.1 Route `/v1/memory/v2/*` on the connector Worker to `serve(request, { prefix: '/v1/memory', caller, store })`; add it to the `agent` reach only in `key-rules.ts`. Test in `api.test.ts`: a computer key gets answers, an API key, the connector and a phone key get 403, and another person's key never reads this space.
- [ ] 3.2 Run `npm run relay:api-doc` in `app/`; update the site's memory page (`site/src/content/docs/api/knowledge-web.md`) for the store route and the five kinds; update `wiki/stack/relay-knowledge-web.md` (the store, `0017`, the kinds map).

## 5. Relay Everything's plugin

- [ ] 5.1 Write `scripts/copy-plugin-memory.mjs` (design §6: the file list, the skill with the plugin's script path) and run it to make `plugin/memory/` and `plugin/skills/memory/`. Write `plugin/test/memory-copy.test.mjs`: it fails when the copy differs from the source, or a copied file imports one that was not copied. Add the script to the plugin release steps in `wiki/stack/relay-chats.md`.
- [ ] 5.2 Write `plugin/memory-profile.mjs` (design §6): `connect` (none when memory is off, not connected, saving off, or the repo has its own memory), `topics` from the knowledge copy, `lookup` for notes and chats on a topic, `sessionStart` for the sync. Test in `plugin/test/memory-profile.test.mjs` with `fake.mjs`: each part and each no-store case; a failed lookup adds nothing.
- [ ] 5.3 Add the setup choice to `plugin/bin/connect.mjs` (`memory` kept in `computer.json`, an older file reads as off) and `/relay:memory on|off` as a skill. Test in `connect.test.mjs`: yes, no, and an older file.
- [ ] 5.4 Change `plugin/bin/hook.mjs` and `hooks/hooks.json` to the three cases in design §6 (repo memory, memory on, memory off), with `WONG_MEMORY_PROFILE` set for the copy's scripts, and add `PreToolUse`. Test in `hook.test.mjs`: each case runs the right scripts, a topic is added once, chat saving runs in all three, and each hook ends within its timeout.
- [ ] 5.5 With memory on, `relay.mjs topic` uses the copy's pull and adds notes and chats. Update `skills/ask`, the skill tests, `plugin/README.md` (the memory choice, what memory saves and where, that a repo's own memory wins), the site's Claude Code and Codex pages, and version `0.5.0` in `plugin/.claude-plugin/plugin.json`.

## 6. Checks

- [ ] 6.1 Run `npm test` in `app/`, `node --test plugin/test/`, `node scripts/product-name.test.mjs`, `node scripts/public-check.mjs`, and `openspec validate relay-memory-plugin --strict --no-interactive`.
- [ ] 6.2 In a scratch Claude Code config, install `relay@relay` from this checkout: `claude plugin list` shows one plugin. With memory on, in a scratch repo with no memory, a chat start prints memory's summary from the local stand-in person's space; in a WongStack-install checkout, it prints only the repo's summary. Repeat the scratch-repo check in Codex.
- [ ] 6.3 `/save`, then on staging with a key made on this computer ([on this computer](../../../wiki/stack/relay-ai-connector.md#on-this-computer)): with memory on, the plugin saves, replaces and searches a fact; a phone key is refused.
