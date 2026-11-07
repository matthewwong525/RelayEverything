# Remove the old shared Relay Everything tables

**Status:** in-progress
**Branch:** fancy-dinosaur
**Open questions:** none

## Why

Each person's notes, health, places, chats, devices and webhooks now live in their own space. The owner's move ran on 2026-11-06 with `result=ok`. The old shared tables still sit in the database, with the commands and doors that only read them. Nobody uses the app yet, so they go now, in one step, with no checks for servers that have not moved.

## What Changes

- **The old shared tables are gone, live and preview.** The database keeps only accounts, sign-ins and device keys. Each person's data stays in their own space. This can't be undone.
  ```mermaid
  flowchart LR
    A["Shared database"] --> B["Accounts, sign-ins, device keys"]
    A -.-x C["Old notes, health, places, chats, devices, webhooks"]
    D["Each person's space"] --> E["Their notes and everything else"]
  ```
- **The one-time move is gone.** The move command, the server's move door and its tickets go. A self-hosted server's update no longer moves old data.
  ```mermaid
  flowchart TD
    A["Update"] --> B["Database changes"] --> C["New server live"]
    C -.-x D["Move old data"]
  ```
- **The old key command is gone.** Every device gets its key from *Add a device* on the page, a self-hosted server too.
  ```text
  Before: the key command, or Add a device
  After:  Add a device
  ```
- **The old AI connector address stops answering.** An AI app still connected at the relay-ring connector connects again at the Relay Everything connector.
  ```mermaid
  flowchart LR
    A["AI app"] -.-x B["Old relay-ring connector"]
    A --> C["Relay Everything connector"] --> D["Your space"]
  ```

Non-goals: the old device keys, the AI connector's old sign-in apps and the old connector's Workers. They go by hand, each confirmed, apart from this change. The old relay-ring address keeps forwarding.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are in `.env`.
- **Your yes to remove the live tables**: Ready, given on 2026-11-07 ("just hard remove no one is using the app rn"). The live database holds 2 old device rows and no notes.

## Capabilities

### Modified Capabilities

- `relay-person-spaces`: the move of old data is removed; the shared database holds no person's data.
- `relay-self-host`: an update no longer moves old data from before spaces.
- `relay-server-address`: the old connector's 30 days of answering end now.

## Impact

- `schema/migrations/`: a new migration drops the 10 old `relay_*` data tables and `relay_move_tickets` in `relay-everything-db`, `relay-everything-db-staging` and each self-host's database.
- Removed: `scripts/relay-move-to-space.mjs`, `scripts/relay-device-key.mjs` and their tests; `app/worker/apps/relay/move.ts` and its test; the `move` caller kind, the `import`, `counts` and recording-adopt calls on a space.
- `app/worker/relay-only.ts`, `app/worker/spaces-worker.ts`, `app/worker/apps/relay/space.ts`, `self-host/setup.mjs` (and its test and templates), `scripts/check-private-access.mjs` and its test, `scripts/product-name.test.mjs`.
- Docs: `AGENTS.md`, `wiki/relay-spaces.md`, `self-host/SETUP.md`, `site/src/content/docs/api/keys.md`, `site/src/content/docs/start/run-your-own.md`.

## Decision log

**2026-11-07** — Asked how to remove the old tables, since a self-hosted server updates its database before its move → chose "literalyl it doesn't matter just hard remove no one is using the app rn".
**2026-11-07** — Asked whether to also remove the older relay-ring connector parts → chose "Yes, remove them too (Recommended)".
**2026-11-07** — Assumed: the move and the old key command go with the tables, because with a hard remove nothing is left for them to read.
**2026-11-07** — Assumed: the Access removals (old device key, the AI connector's sign-in apps and secrets, the relay-ring connector) run by hand as a to-do outside this change, because they change no repo file; this change only drops the spec promise they break.
**2026-11-07** — Assumed: the preview's test rows go too, because the preview runs the same database change first.
**2026-11-07** — Assumed: the old recordings in the bucket stay, because the live move found no notes, so the old folder holds none.
**2026-11-07** — Assumed: each space keeps its own `relay_devices` columns as they are, because that is a space change, not this one.
- **2026-11-07** — Check: `app/worker/apps/relay/move.test.ts` deleted with `move.ts`, because the move's route is gone and nothing is left for it to test.
- **2026-11-07** — Check: `scripts/relay-move-to-space.test.mjs` deleted with its script, because the move command is gone.
- **2026-11-07** — Check: `scripts/relay-device-key.test.mjs` deleted with its script, because the old key command is gone.
**2026-11-07** — Assumed: the old tables' made-up rows leave `schema/seed.sql`, because the preview's reset applies the seed after the migrations, and a row for a dropped table fails it.
**2026-11-07** — Assumed: the company app's own login check (`login-management.ts`) drops its "Relay devices" allowance too, as `check-private-access.mjs` does, because the policy goes by hand before this change.
**2026-11-07** — Assumed: `mobile/` stays as it is, though its README and two comments still name the old key command, because a `mobile/` change starts the phone builds and a release; a later phone change fixes the words.
**2026-11-07** — Assumed: the AI connector's tests read those made-up rows from `app/tests/relay-space-rows.sql`, and `space-schema.test.ts` now checks that D1 keeps only the directory and a space each person's tables, because with no move the two schemas need not match.
**2026-11-07** — Asked to delete each hand step before acting → chose "Delete it" for the old device key and the company login's "Relay devices" rule, "Delete them" for the relay-everything and relay-ring AI connector sign-in apps and for the connector's 10 `ACCESS_*` secrets; all done.
**2026-11-07** — Asked to delete a second "Relay devices" rule found on the retired relay-ring login (c148207d), which kept the old key from being deleted → chose "Delete both"; done.
**2026-11-07** — Asked to delete the relay-ring-mcp Workers, live and preview → chose "Delete them"; done.
- **2026-11-07** — Check: the 3 `import` and `counts` tests in `app/worker/spaces-worker.test.ts` deleted, because a space no longer has those calls.
- **2026-11-07** — Check: the move route test in `app/worker/relay-only.test.ts` deleted, because the route is gone.
- **2026-11-07** — Check: the 2 move tests in `self-host/setup.test.mjs` deleted, because an update no longer moves old data.
- **2026-11-07** — Check: the test in `app/worker/apps/relay/space-schema.test.ts` that compared the shared database's tables with a new space's deleted, because the shared database no longer holds a person's tables; the new tests check each side apart.
**2026-11-07** — Assumed: `AGENTS.md`'s health and location line now says the data lives in each person's own space, because the shared database no longer holds those tables.
**2026-11-07** — Saved for final acceptance inside `/ship`: the build, the review fixes and the hand deletions are done; the preview check of task 6.2 follows.
