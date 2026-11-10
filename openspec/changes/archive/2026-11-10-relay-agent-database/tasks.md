# Tasks

## 1. The server

- [x] 1.1 Add the `Workbench` class to `spaces-worker.ts` with `run`, `tables` and `deleteEverything` and the limits of design §2; bind `WORKBENCHES` in `wrangler.spaces.jsonc` (tag `v2`), in each Worker that binds `SPACES`, and in the self-host templates. Test in `spaces-worker.test.ts`: make a table and read it back, a batch is all or none, `relay_notes` is no such table, each limit refuses, a blob reads as base64.
- [x] 1.2 Open the workbench in `space.ts` and delete it in `deleteEverything`; add `db` and `db_tables` to the web API. Test in `api.test.ts`: a computer key runs commands, API and connector callers are refused, the space is unchanged; in `account.test.ts`: after delete, the workbench is empty.

## 2. The plugin

- [x] 2.1 Add `relay.mjs db`, `db --file` and `db tables`, and a line in the `ask` skill; version `0.5.1`. Test in `plugin/test/`.

## 3. Docs and checks

- [x] 3.1 Document it: `wiki/relay-spaces.md`, `npm run relay:api-doc`, the site page `api/agents-database.md`, `plugin/README.md`.
- [x] 3.2 Run `npm test` in `app/`, `node --test plugin/test/`, `node scripts/product-name.test.mjs`, `node scripts/public-check.mjs`, and `openspec validate relay-agent-database --strict --no-interactive`.
