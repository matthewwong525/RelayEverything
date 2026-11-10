# Tasks

## 1. The start repository and the format

- [x] 1.1 Write `schema/knowledge/README.md` and `schema/knowledge/FORMAT.md` (facts, pages with a one-line summary, links and the way to look, as the design's default rules), in plain words, one screen each, with a sample fact and a sample page in `FORMAT.md`; check with `node scripts/product-name.test.mjs`
- [x] 1.2 Write `scripts/relay-knowledge-setup.mjs [--staging]`: makes the namespace and the `start` repo, pushes the two pages with a short token, and prints `ok` lines; test its plan-making part with a fake fetch in `scripts/relay-knowledge-setup.test.mjs`; run it for staging and see `ok`
- [x] 1.3 Make `scripts/publish-relay-server.mjs` run the setup script before the server publish, and test the order in its test

## 2. The memory table

- [x] 2.1 Add `schema/space-migrations/0016_memory.sql` (`relay_memory`, `relay_memory_tags`, `relay_memory_columns` seeded with `kind` and `text`, `relay_memory_column_changes`) and its check in `space-schema.test.ts`; add made-up facts to the space's sample data
- [x] 2.2 Add `POST /v1/memory`, `GET /v1/memory`, `GET /v1/memory/{id}` and the connector's `memory` and `read_fact` tools from one answer each; test add-only (no route changes or deletes), replace marks the old fact, a resent `clientId` stored once, no tag, no source or a required column missing refused, word, tag, source, column and time search, live only unless `all`, a phone key refused, and Ana never sees Ben's facts, in `app/worker/relay-mcp/tools.test.ts` and `api.test.ts`
- [x] 2.3 Add `GET` and `POST /v1/memory/columns`; test add, change and remove, a type change, a kept name and a 21st column refused, a removed column's values still read, a wrong type refused on a new fact, a change kept with its device, an API key and the connector refused a change, and a name or filter made to look like SQL changing nothing, in `app/worker/apps/relay/memory.test.ts`
- [x] 2.4 Add `relay_note_tags` and `relay_tag_changes` to the migration, `POST /v1/memory/{id}/tags`, `POST /v1/notes/{id}/tags`, and `tag=` on `GET /v1/notes` and the connector's `search`; test add and remove kept with the device, a fact's last tag refused, a parent tag finding its children, a note's words unchanged, a phone key and an API key refused a change, and a deleted note's tags gone, in `app/worker/apps/relay/memory.test.ts`
- [x] 2.5 Add `facts`, `fact <id>`, `add-facts`, `columns`, `change-columns`, `tag` and `notes --tag` to `plugin/bin/relay.mjs`, and test them against the fake server in `plugin/test/relay.test.mjs`

## 3. The web on the server

- [x] 3.1 Add the `KNOWLEDGE` Artifacts binding to `app/wrangler.relay.jsonc` (live and staging), raise wrangler to the version the binding needs, run `npx wrangler types`, and check `npm run build` in `app/`
- [x] 3.2 Add `POST /v1/knowledge/access`: computer keys only, get or fork the person's repo, a one-hour write pass, 501 with no binding; test a computer key, a first ask that forks, a phone key, a turned-off key, an API key, another person's repo name never reachable, and no binding, in `app/worker/apps/relay/knowledge.test.ts`
- [x] 3.3 Delete the repo in `accountDelete`, after the space; test it in `account.test.ts`, with a missing repo passing
- [x] 3.4 Run `npm run relay:api-doc` in `app/`, and add the route to the API reference page

## 4. The plugin's copy of the web

- [x] 4.1 Write `plugin/bin/knowledge.mjs` (`sync`, `status`) by the design: clone or pull and push with the pass in the environment only, both versions kept on a conflict, a clear line with no git or no web on the server; test with a local bare repo standing in for Artifacts in `plugin/test/knowledge.test.mjs`, including two copies writing different pages, a second sync within 15 minutes that makes no network call, a local change or `--now` that syncs anyway, and that no pass reaches a file or the remote URL
- [x] 4.2 Add `knowledge.mjs` to the plugin's no-secrets test, and say in `plugin/README.md` where the copy lives

## 5. Docs

- [x] 5.1 Add the website page `site/src/content/docs/api/knowledge-web.md` with the format, and a check that it matches `schema/knowledge/FORMAT.md`; note the paid plan on the self-host page; add the memory routes to the API reference and the connector page, a part for people who build their own plugin, and a line to *Delete my account* on the site
- [x] 5.2 Write `wiki/stack/relay-knowledge-web.md` (the namespaces, the start repo, the setup script, the pass), linked from `wiki/relay-spaces.md`

## 6. Checks

- [ ] 6.1 Run `npm test` in `app/` and `plugin/`, `node scripts/public-check.mjs`, and `node scripts/product-name.test.mjs`; all pass
- [ ] 6.2 On staging: connect a computer, run `knowledge.mjs sync`, see `README.md` and `FORMAT.md`, add a column, add two facts (one replacing the other) and find them by tag from the connector, add a page, sync from a second folder and see it; a phone key is refused; read the account's Artifacts usage before and after to see whether an empty pull and a pass count as operations, and write the answer in the wiki page
- [ ] 6.3 `/save` after the checks, then check the staging preview against each scenario in the specs
