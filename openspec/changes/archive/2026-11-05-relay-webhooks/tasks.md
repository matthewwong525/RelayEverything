# Tasks

Builds on `relay-app-first-version`, published to `main`. Branch from the current `main`.

## 1. Setup (Cloudflare, wrangler, schema)

- [x] 1.1 Create queues `relay-webhooks` and `relay-webhooks-staging`. Bind `RELAY_WEBHOOKS` as producer and consumer (`max_batch_size: 10`, `max_retries: 10`) for production and staging in `app/wrangler.jsonc`. Then verify `wrangler types` adds the binding to `Env`
- [x] 1.2 Add the migration for `relay_outbox` with its four triggers and the fill from existing rows, `relay_webhooks` and `relay_webhook_attempts`, plus seed rows in `schema/seed.sql`. Add a migration test: an insert, a place filled in and a duplicate upload each log the right entry (or none), and existing rows are logged in time order. Verify that the local migration and seed apply cleanly
- [x] 1.3 Add `standardwebhooks` as a dev dependency of `app/`

## 2. Core hook (app/worker)

- [x] 2.1 Add `handleAppQueue` and `handleAppSchedule` to `app/worker/apps/index.ts`, and the `queue` handler and schedule call to `app/worker/index.ts`. Add tests for routing by queue name with and without `-staging`, an unknown queue, and memory bindings absent from the app's env

## 3. Server (app/worker/apps/relay/webhooks)

- [x] 3.1 Write `format.ts` (the zod schema for v1 and the builders for each type, with audio as base64) and `sign.ts` (Standard Webhooks signing). Add tests that build each type from seed-shaped rows, and that `standardwebhooks` verifies a signed body and rejects a changed body or a wrong secret
- [x] 3.2 Write `address.ts` (the https, host and IP-range checks). Add tests for each refused range, `http:`, user info, the site's own host, and an allowed public host
- [x] 3.3 Write `wake` and the sender: the lease, grouping log entries by the webhook's kinds, freezing the group in `pending_seq`, build, sign, POST with no redirects and a 15 s timeout, moving the cursor on 2xx, the retry schedule, `failing_since` after the last try, the address re-check, the recording-not-yet-saved wait, and skipping a deleted note. Add tests for 2xx, 503 then 200 with an identical retry body and id, a timeout, a redirect, the final failure then *Try again now* sending everything waiting in order, two consumers racing for one webhook, rows arriving during a run, a paused webhook, and a removed webhook
- [x] 3.4 Write the backfill (move the cursor back to a date) and the sweep (wake every webhook whose cursor is behind the log, and prune attempts older than 30 days), with a manual sweep trigger reachable on staging only. Add tests for the trigger being refused on production, a backfill from a date, ticked kinds only, a second backfill, and the sweep's two jobs
- [x] 3.5 Write the owner routes `webhooks`, `webhooks/update`, `webhooks/remove`, `webhooks/secret`, `webhooks/test`, `webhooks/resend` and `webhooks/retry` in `api.ts`, user-only. Add tests for a device token being refused, the secret returned only on create and replace, a refused address, and the test result shape
- [x] 3.6 Call `wake` from `pebble` (after the R2 put), `notes`, `health` and `locations` when they stored a row or filled a place. Extend their tests: a stored note wakes each active webhook, a duplicate or a Pebble test event wakes nothing, and a queue error still answers success

## 4. Relay page (app/src/apps/relay)

- [x] 4.1 Build from the prototype diff `.scratch/relay-webhooks-prototype.diff`, wired to the real routes. Add the *Send to your database* section below the notes: webhook cards with a status tag, the last result and next try, *Send a test* with its answer, *Send past data* with a date, *New secret*, *Pause* and *Resume*, *Try again now*, and *Remove* with a confirmation. Add the *Add a webhook* dialog (with a sensitive-data line under the health and location ticks) and the one-time secret dialog. Add tests for each state and each action, using the shadcn parts the design lists

## 5. Public format (site/)

- [x] 5.1 Generate `site/public/webhooks/v1.schema.json` from `format.ts`. Add an `app/` test that fails when the committed file differs, and run `npm run relay:api-doc` in `app/` so the Routes page lists the webhook routes
- [x] 5.2 Write `site/src/content/docs/connections/your-database.md` (adding a webhook, the envelope, each type with an example, signing, retries, upsert advice, a 16 MB body limit, Postgres tables) and `site/public/webhooks/receiver.mjs` (`node:crypto` and `node:sqlite`, no packages). Replace the *Coming* note in `connections/index.md` with a link, and update `site/sidebar.mjs`. Add an `app/` test that runs the receiver against bodies signed by the real sender, and one that `standardwebhooks` verifies them
- [x] 5.3 Run `npm test` in `site/` and `node scripts/publish-relay-site.mjs --ref HEAD --dry-run`. Then verify that it prints `result=ready`, which means the privacy guard passes the new page and files

## 6. Project notes

- [x] 6.1 Update `AGENTS.md`'s Relay section: health and location also go to the webhooks the owner ticks for them, and nowhere else

## 7. Verification

- [x] 7.1 Run the app's full suite (`npm test` in `app/`), `node --test scripts/*.test.mjs` and `node scripts/public-check.mjs`, which must print `result=clean`
- [x] 7.2 `/save`. Then, on the preview: run the example receiver locally behind a `cloudflared` quick tunnel, add it as a webhook with health ticked, and see *Send a test* answer 200. Send a typed note and a health sync from a staging device key, and see the rows in the receiver's SQLite. Stop the receiver for 5 minutes, send three notes, restart the receiver, and see all three arrive in order after a retry. Run *Send past data* from a week ago and see the earlier notes arrive. Finally remove the webhook and stop the tunnel. Then run `node scripts/publish-relay-site.mjs --ref HEAD --staging` and check the *Your own database* page on the staging website
