# Rename Relay in Cloudflare and move its data

**Status:** ready-to-ship
**Branch:** eager-hedgehog
**Open questions:** none

## Why

Relay is now Relay Everything, and the ring may never launch. But your private Relay site, its data and its tools in Cloudflare still carry the old ring name. Some of them can't be renamed, so the data has to move to new ones with the new name.

## What Changes

- **Your private Relay site gets a new address: app.relayeverything.com.** It keeps the same login, and your phone's and Pebble's keys keep working there. New device-key QR codes show the new address.
  ```text
  Before                     After
  relay-ring.matthewwong525  app.relayeverything.com
  .workers.dev               (same login, same keys)
  ```
- **The old address keeps working for 30 days.** It passes each request on to the new site, so the phone and the Pebble webhook keep sending while you change their server address. A web page you open at the old address takes you to the new one.
  ```mermaid
  flowchart TD
    P["Phone, Pebble"] --> O["Old address"]
    B["Your browser"] --> O
    O -->|"passed on, or taken to"| N["app.relayeverything.com"]
  ```
- **Your data moves to new storage with the new name, and stays in your Cloudflare account.** Notes, recordings, health, places, memory facts and transcripts are copied from one Cloudflare store to the other. Nothing passes through this computer or goes into a file. The copy is checked by counting every table's rows and every bucket's files on both sides.
  ```text
  Old store            New store        Check
  relay-ring-db     -> relay-everything-db       rows match
  relay-ring-notes  -> relay-everything-notes    files match
  relay-ring-memory -> relay-everything-memory   rows, files
  ```
- **Your AI connector gets the new name too.** Its new address is relay-everything-mcp, with a new sign-in. The Claude app stays connected to the old address for 30 days, and it reads your current data there. You add the new address in the Claude app when it suits you.
- **A short pause at the switch.** For a few minutes, the old site answers *try again soon* while the last new notes copy over. The phone keeps them and sends them after. The Pebble tries again for about 10 minutes, so a ring note in the pause still arrives. Previews get the same move first, as a rehearsal.
- **Everything else gets the new name too**: the site's helper parts, the previews, the login apps, the knowledge store, and the names in this project's settings, scripts and docs. The old check runner and the old copy of the code, unused since the move to GitHub, get no new name: they go with the old stores at day 30.
- **The old stores are deleted only after you say yes, after the 30 days.** A reminder comes then, with the counts from the copy. Deleting them can't be undone.

Non-goals: the move to GitHub (its own change), a new login or new device keys, renaming the public website's own parts, changing the phone app's code, and changing what Relay does.

## What the build needs

- **The GitHub move, published**: Ready, it is live at github.com/matthewwong525/RelayEverything.
- **The MCP server and offline notes, live**: Ready, both are live.
- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are in `.env`, and GitHub holds the deploy token. The first build step checks that both can make the address app.relayeverything.com, and that this computer's can make databases, buckets and Workers.
- **The domain relayeverything.com**: Ready, it is in your Cloudflare account and the public website already uses it.
- **Your time at the switch, and your yes before any delete**: Ready, nothing to give now. The build tells you when the pause starts and when the copy checks out. You change the server address on the phone and in the Pebble app when it suits you in the 30 days, and the day-30 reminder asks before any delete.

## Capabilities

### New Capabilities
- `relay-server-address`: the private Relay site's address app.relayeverything.com, the 30-day forward from the old address, and the address in new device keys.
- `cloudflare-data-move`: copying a D1 database or R2 bucket to a newly named one inside the Cloudflare account, proven by counts, with the old one kept until the owner says to delete it.

### Modified Capabilities

## Impact

- Cloudflare, new: Workers `relay-everything`, `relay-everything-staging`, `relay-everything-line`, queues `relay-everything-webhooks` and `relay-everything-webhooks-staging`, `relay-everything-mcp`, `relay-everything-mcp-staging` (with new sign-in KVs and Access for SaaS apps `relay-everything AI connector` and `(staging)`); D1 `relay-everything-db`, `relay-everything-db-staging`, `relay-everything-memory`; R2 `relay-everything-notes`, `relay-everything-notes-staging`, `relay-everything-memory`; Artifacts repo `relay-everything-knowledge`; custom domain `app.relayeverything.com` on the `relayeverything.com` zone. Access apps `WongStack relay-everything (relay-everything)` and `previews`, which let in the same people, checker and device keys.
- Cloudflare, temporary: the `relay-ring` Worker becomes a forwarder for 30 days; `relay-ring-mcp` reads `relay-everything-db` for 30 days; a one-off copy Worker `relay-everything-move` exists only during the copy.
- Cloudflare, deleted after Matthew's yes on day 30: `relay-ring`, `relay-ring-staging`, `relay-ring-line`, the old D1 databases and R2 buckets, `relay-ring-knowledge`, `relay-ring-mcp` and `relay-ring-mcp-staging` with their KVs and SaaS apps, the two old Access apps, the keys `relay-ring-access` and `relay-ring-cloudflare-read`, the queues `relay-webhooks` and `relay-webhooks-staging`; and, unused since the GitHub move, the check runner `relay-ring-checks` (Worker, Workflow, container, R2 bucket), the Artifacts code repo `wongstack/relay-ring`, and the `relay-ring-deploy` API token.
- Code: `app/wrangler.jsonc`, `app/wrangler.line.jsonc`, `app/wrangler.relay-mcp.jsonc`, `scripts/relay-mcp-setup.mjs` and the `relay-ring` fixtures in script tests, `wiki/stack/relay-ai-connector.md`, `app/worker-configuration.d.ts`, `app/package.json`, `.agents/.wong-stack.json`, `app/wrangler.jsonc` drops the `CODE_CHECKS` binding, `scripts/check-runner/` goes if WongStack's GitHub route doesn't need it, `scripts/relay-device-key.mjs`, `scripts/publish-relay-site.mjs` and its test, `AGENTS.md`, `wiki/`. New: `scripts/cf-move-data.mjs` with its Worker and test, `scripts/relay-forward/`, a wiki page on moving data to a new name.
- This computer: `~/.relay-ring/device-keys/` moves to `~/.relay-everything/device-keys/`; `cloudflared access login` for the new address.
- Depends on: the GitHub move (`relay-everything-open-source`, b355538), `relay-ai-connector` (befaa24), `relay-offline-by-default` (4edc1ff), all on `main`.

## Decision log

- **2026-11-05** — Asked (in the "Relay Everything" chat) what gets the new name → chose everything, the Cloudflare side too, with the base name relay-everything.
- **2026-11-05** — Asked where the private site lives → chose app.relayeverything.com; the old workers.dev address forwards for 30 days; new device-key QR codes carry the new address.
- **2026-11-05** — Asked how to handle stores that can't be renamed → chose copy to new stores, check by row and file counts, then delete the old ones only after Matthew says yes.
- **2026-11-05** — Asked where health and location data may go during the copy → chose only inside Matthew's Cloudflare account, never in a file in the repo.
- **2026-11-05** — Asked when to build → chose after the GitHub move publishes and the MCP server and offline-notes builds are live.
- **2026-11-05** — Assumed: the old address passes requests on rather than sending a redirect, because the phone's HTTP client and the Pebble webhook don't follow a redirect on a send; only page loads in a browser get a redirect.
- **2026-11-05** — Assumed: the copy runs in a one-off Worker bound to both old and new stores, not `wrangler d1 export`, because an export writes health and location rows to a file on this computer.
- **2026-11-05** — Assumed: a pause of a few minutes at the switch, because a copy with no pause can miss an edit made between the bulk copy and the switch; the phone's offline queue and the Pebble's 10-minute retry cover the pause.
- **2026-11-05** — Assumed: previews move first, as a rehearsal, with the same tool and no 30-day forward, because no device sends to the preview address.
- **2026-11-05** — Assumed: one question to delete the old stores, at day 30 with the forwarder, not right after the copy, because the old stores are a free fallback while the forward still runs.
- **2026-11-05** — Assumed: the copy tool is a general script with a wiki page, because moving a Cloudflare store to a new name is repeatable and its rules (inside the account, counts only) apply again.
- **2026-11-05** — Assumed: the check runner `relay-ring-checks`, the Artifacts code repo and the `relay-ring-deploy` token are deleted at day 30, not renamed, because the GitHub move left them unused and kept them only as a fallback until this change; a renamed unused runner would carry the new name for nothing.
- **2026-11-05** — Assumed: the website pages need no change, because they never name the private site's address (`<your-relay-server>`); the site guard gains a rule refusing app.relayeverything.com.
- **2026-11-05** — Assumed: the plan drops the app-copy script's rename and its run after publish, and adds `scripts/public-check.mjs` to the checks, because the GitHub move (b355538, now on this branch) removed `scripts/publish-relay-app.mjs` and already changed `WONG_CODE_REPOSITORY` and the `delivery` record.
- **2026-11-05** — Assumed: build and publish without asking Matthew, picking the recommended option at each choice, because the orchestrator chat, acting for him, approved *Build and publish*; the day-30 deletes still wait for his yes, and his steps on the phone, the Pebble and the Claude app go into an open thread.
- **2026-11-05** — Assumed: the AI connector moves to new Workers `relay-everything-mcp` (and staging) at their workers.dev addresses, made by its setup script, and the old `relay-ring-mcp` reads the new database for 30 days, because an AI app's sign-in lives in the old Worker's store and is tied to its address, so a forward can't carry it.
- **2026-11-05** — Assumed: the steps after the merge (hold, copy 2, forward, the checks through the old address, this computer's sign-in, the site update, the day-30 schedule) run as the switch runbook in the design, right after the publish, not as tasks, because a task can't wait for the publish that needs every task ticked first.
- **2026-11-05** — Assumed: the copy check compares each old row and file with the new one, not only counts, because a memory fact written to both stores between the two copies gets the same id on both sides, and a count alone would hide the lost one.
- **2026-11-05** — Assumed: two new login apps for the new site, copies of the old ones with the same people, checker and device keys, not the old apps renamed and repointed, because the privacy check needs an app to cover exactly one Worker; repointing would take the login off the live old site and stop every other Relay chat's publish until the switch. Device keys still work: they belong to the account, and the site finds each one in the copied device list.
- **2026-11-05** — Assumed: the old address passes requests on with `fetch` to the new address, which checks the device's key again, not through a direct link between the Workers, because the old login app's pass names the old app and the new site refuses it.
- **2026-11-05** — Assumed: the GitHub deploy key `RelayEverything-deploy` gets Zone Read and Workers Routes Write on the `relayeverything.com` zone only, keeping its other rights, because it had no right to set up `app.relayeverything.com`; this computer's key already had every right the build needs (D1, R2, Workers, KV, Access, Artifacts, the zone).
- **2026-11-05** — Assumed: the names to change, from a search for `relay-ring` (task 1.2). Rename: `AGENTS.md`, `.agents/.wong-stack.json`, `app/package.json`, `app/worker-configuration.d.ts` (regenerated), `app/wrangler.jsonc`, `app/wrangler.line.jsonc`, `app/wrangler.relay-mcp.jsonc`, `scripts/relay-device-key.mjs`, `scripts/relay-mcp-setup.mjs`, the fixtures in `scripts/check-private-access.test.mjs`, `scripts/publish-relay-site.test.mjs`, `scripts/relay-mcp-setup.test.mjs` and `scripts/relay-mcp-trial.test.mjs`, `wiki/stack/relay-ai-connector.md`, and the names in `scripts/check-runner/wrangler.jsonc`. Retire: the `CODE_CHECKS` binding. Keep: the check runner's code in `scripts/check-runner/`, because WongStack ships it and the save step and the code reader import its `run-id.mjs`; its config takes the new name but nothing deploys it.
- **2026-11-05** — Assumed: the new site gets its own sign-in list key and read-only Cloudflare key, made with the old keys' permissions under setup's names, not the WongStack setup step run again, because the step would also rewrite the login apps this change already made; the old keys go at day 30.
- **2026-11-05** — Assumed: `--replace` writes a changed row with an update on its primary key, not `INSERT OR REPLACE`, and leaves out only the columns a `BEFORE UPDATE OF` trigger names, because REPLACE deletes the row first, which `facts_never_deleted` and foreign keys refuse, and because a memory fact's `superseded_by` and a session's progress change between the copies while its words never do; a same-id fact with other words still fails as `differ`.
- **2026-11-05** — Assumed: the copy skips the migration ledgers `d1_migrations` and `schema_migrations` as well as SQLite's, Cloudflare's and FTS5's own tables, because the new side's schema step wrote its own ledger with today's times, which would fail the check on every row.
- **2026-11-05** — Assumed: a table is copied after the tables its rows name, and a link to a row of the same table (a fact's `superseded_by`) goes in after the whole table, because D1 enforces foreign keys and a fact names a later one.
- **2026-11-05** — Assumed: the forwarder drops every `cf-` header but the device's `CF-Access-Client-Id` and `-Secret`, and the old sign-in's assertion, email header and cookie, because Cloudflare sets its own on the new request.
- **2026-11-05** — Assumed: the forwarder's config repeats `relay-ring`'s migrations `line-1` and `line-2`, so the deploy finds tag `line-2` already applied and sends none; task 6.5 drops the list if Cloudflare refuses it.
- **2026-11-05** — Assumed: the install record's machine policy ids are the new apps' checker policies, read from Cloudflare (`f6104024…`, `b1045537…`), and `app/worker-configuration.d.ts` is regenerated without `RELAY_PEBBLE_SIGNING`, which `wrangler types` read from this computer's `.dev.vars`, so the file matches what CI makes.
- **2026-11-05** — Assumed: at the switch the old login app moves off the old address to an unused one, kept for a rollback, so the forwarder runs with no login in front, because the trial showed Cloudflare's login takes the device key's headers off before the Worker sees them; the new address checks every key, and the forwarder holds no data. The trial also showed the forwarder deploys over the old Worker's history and over a Worker with none.
- **2026-11-05** — Assumed: the copy turns off the new database's after-write triggers while it runs, then puts them back and rebuilds the search index, because the webhooks change (talented-catfish, on old staging and soon on main) adds triggers that write an outbox row for each note, and a copy with them on would make a duplicate event for every copied note. The paused triggers' own SQL is saved in `_move_paused_triggers` on the new side, so a stopped run's rerun puts them back; an old-side trigger the new side never had is never added, because its body can name a table the new side lacks.
- **2026-11-05** — Assumed: the new staging database gets the webhooks change's migration from its branch before the rehearsal, because old staging already holds it from that chat's preview, and a rehearsal needs the same tables on both sides; production gets it from `main` like any migration.
- **2026-11-05** — Assumed: the staging rehearsal passes. The first copy failed only on the seeded default task group, whose timestamps differ; the `--replace` pass took them and passed every table, trigger and file in 38 seconds, far under the 5-minute limit. So production copy 1 runs with `--replace` too: the new side is unused then.
- **2026-11-05** — Assumed: the webhooks change's queues get the new name too, `relay-everything-webhooks` and `-staging`, and the app finds its queue handler by that name, because a queue takes one consumer and the old site still consumes `relay-webhooks` until the switch, so the new site's first publish would fail on the old queue. A queue message only says *look now*; the database holds what was sent, so nothing is lost when the old queues go at day 30.
- **2026-11-05** — Assumed: production copy 1 passed on its third run (45 seconds), every table, trigger, search index and file matching. The first run found the webhooks tables, live on the old database since that change published, missing on the new one; the build applied that migration to the new database, emptied the outbox rows its backfill wrote, and ran again. The second run met one inbox item edited on the live site between copy and check.
- **2026-11-05** — Assumed: after the second look, the merge of main brings the Claude Code chats change; its chat keys take the new token name `relay-everything chats <name>`, and the plugin's no-address test also refuses the new site names and `app.relayeverything.com`. Archive checkpoint: every task done, the review found three problems in two rounds and all are fixed.
