# Tasks

## 1. Before the build

- [x] 1.1 Confirm `relay-ai-connector` and `relay-offline-by-default` are on `main` and this branch has them; confirm with the Cloudflare API that `CLOUDFLARE_API_TOKEN` can create D1, R2, Workers, KV, Access apps and edits, Artifacts repos and a custom domain on `relayeverything.com`, and that the GitHub Actions deploy token `RelayEverything-deploy` can deploy a Worker with that custom domain; verify by a read call per permission, and stop naming any missing one.
- [x] 1.2 Grep the repo for `relay-ring` (not `vendor/` or `openspec/changes/archive/`) and list each hit in the Decision log as rename, retire or keep.

## 2. The move tool (`scripts/`)

- [x] 2.1 Write `scripts/cf-move-data/worker.mjs`: paged D1 copy by `rowid` (primary key for `WITHOUT ROWID`), `INSERT OR IGNORE` or `--replace`, no replace on trigger-guarded tables, FTS5 tables skipped; R2 copy of missing or changed keys with metadata; the check with `missing`, `differ` and `extra` counts per table and size and ETag per object; answers only names and counts; refuses a request without `MOVE_KEY`.
- [x] 2.2 Write `scripts/cf-move-data.mjs`: temporary config outside the repo, in-memory key set as a secret through stdin, deploy, paged calls, `result=passed|failed` line, delete of `relay-everything-move` on every exit; `--check-only` checks without copying.
- [x] 2.3 Write `scripts/cf-move-data.test.mjs` with the worker run in Miniflare against two local D1s and two local R2s: a second run doubles nothing; a row added after the first run arrives; `--replace` takes an edited row; a `facts_never_edited`-style table is never replaced, and a same-id different row there fails as `differ`; a `WITHOUT ROWID` table copies; a missing object fails naming the bucket; output holds no row or object content (seeded with a marker string); verify with `node --test scripts/cf-move-data.test.mjs`.
- [x] 2.4 Write `wiki/stack/move-cloudflare-data.md` (why D1 and R2 need a copy, the tool, the inside-the-account rule, the check, the delete only on a yes) and link it from `wiki/stack/README.md`.

## 3. The forwarder and the scripts (`scripts/`)

- [x] 3.1 Write `scripts/relay-forward/worker.mjs` and its `wrangler.jsonc` (name `relay-ring`, `MODE` and `TARGET` vars, no data bindings): `hold` answers 503 with `Retry-After: 60`; `forward` sends browser page loads a 308 to `TARGET` (`https://app.relayeverything.com`) and passes everything else on with `fetch` to the same path and query on `TARGET`, without `Cf-Access-Jwt-Assertion` or the cookie, WebSocket upgrades included.
- [x] 3.2 Write `scripts/relay-forward/worker.test.mjs`: a `POST` with a body and token headers reaches `TARGET` byte-for-byte, with the old assertion and cookie gone; a page `GET` gets 308 with path and query kept; `hold` answers 503 for both.
- [x] 3.3 Change `scripts/relay-device-key.mjs`: default server from the production custom domain in `app/wrangler.jsonc`, hand-over folder `~/.relay-everything/device-keys`, token name prefix `relay-everything device`; update its test so a new key's page and QR code show `https://app.relayeverything.com`.
- [x] 3.4 Change `scripts/publish-relay-site.mjs` so `privateValues` takes `routes[].pattern` from `app/wrangler.jsonc`; add tests that a page naming `app.relayeverything.com` is refused and one naming `relayeverything.com` passes; rename the `relay-ring` fixtures in its test.
- [x] 3.5 Change `scripts/relay-mcp-setup.mjs`'s SaaS app name to `relay-everything AI connector`, and the `relay-ring` names in `scripts/relay-mcp-setup.test.mjs`, `scripts/relay-mcp-trial.test.mjs` and `scripts/check-private-access.test.mjs`.

## 4. Rename in the repo (`app/`, `.agents/`, docs)

- [x] 4.1 Rename every name in `app/wrangler.jsonc`, `app/wrangler.line.jsonc` and `app/wrangler.relay-mcp.jsonc` (Workers, D1 names and IDs, R2 buckets, `LIVE_LINE` and `RELAY_MCP` targets, `RELAY_MCP_ADDRESS`, `WONG_KNOWLEDGE_REPOSITORY`, `CF_ACCESS_WORKER_ID` per environment, local names); add the production custom domain route and staging's empty routes; remove the unused `CODE_CHECKS` binding, and rename the names in `scripts/check-runner/wrangler.jsonc` (its code stays: WongStack ships it); regenerate `app/worker-configuration.d.ts`; rename `db:migrate:*` in `app/package.json`.
- [x] 4.2 Update `.agents/.wong-stack.json`: `access.workers` names and IDs, `memory` database ID, bucket and worker URL, `companyApi.origin`, `liveLine.workers`, `knowledge.repo`.
- [x] 4.3 Update `AGENTS.md` (`~/.relay-everything/device-keys/`), `wiki/stack/relay-ai-connector.md` (names, addresses, the 30 days on the old address) and every other page from 1.2.

## 5. Check the code

- [x] 5.1 Run the pre-checks once: `node .github/scripts/checks.mjs --worktree`, `node --test scripts/`, `node scripts/public-check.mjs`, and `npm run relay:api-doc` in `app/` with no diff. Fix every failure; loosen no check. Verify `grep -rn relay-ring` outside `vendor/` and archives returns only the forwarder config, the move notes and the old-address notes.

## 6. Make the new Cloudflare parts (outward)

- [x] 6.1 Create D1 `relay-everything-db`, `relay-everything-db-staging`, `relay-everything-memory` and R2 `relay-everything-notes`, `relay-everything-notes-staging`, `relay-everything-memory`; apply `schema/migrations` to both app databases and the memory skill's migrations to the memory database; verify `wrangler d1 migrations list` shows none pending.
- [x] 6.2 Upload 404 placeholders to `relay-everything`, `relay-everything-staging` and `relay-everything-line`, and give `relay-everything` the custom domain `app.relayeverything.com`; make the two new Access apps on the two app Workers, copies of the old apps' settings and policies (same people, checker and device tokens), and leave the old apps unchanged; make `relay-everything-access` and `relay-everything-cloudflare-read` with the old keys' permissions and store them, and `RELAY_PEBBLE_SIGNING`, as the new Workers' secrets; verify with `node scripts/probe-private-access.mjs --url` on both new workers.dev addresses and on `app.relayeverything.com` that each asks for the login.
- [x] 6.3 Make the Artifacts repo `relay-everything-knowledge`, mirror-push every ref from `relay-ring-knowledge`, and verify `git ls-remote` matches on both.
- [x] 6.4 Run `node scripts/relay-mcp-setup.mjs --staging` and `node scripts/relay-mcp-setup.mjs` with the renamed config; verify a second run prints `ok` on every line, and `node scripts/relay-mcp-trial.mjs` passes against `relay-everything-mcp-staging`.
- [x] 6.5 Try the forwarder deploy over a throwaway Worker that has `relay-ring`'s Durable Object migration history (`line-1`, `line-2`), and onto a Worker with none; verify both deploy. Put it behind a throwaway Access app, then with none, in `forward` mode toward `app.relayeverything.com`; verify a checker call through it reaches the new site, a call with no key gets the new login, and a page load gets 308. Delete the throwaway Workers and app.

## 7. Rehearse on staging and copy production (outward)

- [x] 7.1 Run `node scripts/cf-move-data.mjs --d1 relay-ring-db-staging=relay-everything-db-staging --r2 relay-ring-notes-staging=relay-everything-notes-staging`; verify `result=passed`.
- [x] 7.2 Upload the preview to `relay-everything-staging` with `scripts/cf-preview.sh`; verify its Relay page shows the copied staging notes, health and places, and a staging device key sends a note.
- [x] 7.3 Run the staging copy again with `--replace` and time it; write the time and the counts in the Decision log; a run over 5 minutes stops the build to rethink the hold.
- [ ] 7.4 Run production copy 1: `--d1 relay-ring-db=relay-everything-db --d1 relay-ring-memory=relay-everything-memory --r2 relay-ring-notes=relay-everything-notes --r2 relay-ring-memory=relay-everything-memory`; verify `result=passed`. Then `/ship`, and run the switch runbook in the design right after it merges.
