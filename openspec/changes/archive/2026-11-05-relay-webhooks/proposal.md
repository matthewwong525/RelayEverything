# Relay webhooks to your own database

**Status:** ready-to-ship
**Branch:** talented-catfish
**Open questions:** none

## Why

Relay keeps your notes, but you may want them in your own database too, next to your other data, in a shape you can rely on. A webhook sends each new note to an address you own, a few seconds after Relay gets it, in one documented format. You can build your own tools on your notes without asking Relay for them.

## What Changes

- **Relay sends your data on, in order, with nothing skipped.** Your phone syncs to Relay's server. Then the server sends each new note to every webhook you added, a few seconds later. Each webhook keeps its place in a list of everything Relay stored. If your database is down, Relay keeps that place and tries again for a day. After that it waits for *Try again now*, then sends everything from where it stopped. A note that arrives twice has the same id, so your database keeps one copy.
  ```mermaid
  flowchart TD
    A["Ring"] --> B["Phone"]
    B -->|"sync, when sending is on"| C["Relay server"]
    C -->|"signed message"| D["Your database"]
    C -.->|"keeps its place, retries"| D
  ```
- **You choose what goes.** Each webhook sends notes, with their words, recording and place. Health and location are sensitive, so they go only if you tick them for that webhook.
  ```picture
  Before: pictures/before.png
  After: pictures/add.png
  Try it: https://relay-webhooks-relay-ring-staging.matthewwong525.workers.dev/apps/relay/
  ```
- **A webhooks section on the Relay page.** It lists each webhook with its last result. You can send a test, send past data from a date, make a new secret, pause it, or remove it. When you add a webhook, its secret shows once, so your database can check that each message came from Relay.
  ```picture
  Before: pictures/before.png
  After: pictures/section.png
  Secret, shown once: pictures/secret.png
  Try it: https://relay-webhooks-relay-ring-staging.matthewwong525.workers.dev/apps/relay/
  ```
- **Past data on request.** A new webhook gets only new data. *Send past data* sends everything from a date you pick, in the same format, so your database can catch up.
- **One set format, written down in public.** Every message has the same envelope and a version number, and is signed by the open Standard Webhooks method, which has libraries for most languages. The Relay website gets a *Your own database* page with the format, an example receiver to copy and the tables to make in Postgres. It replaces the *Coming* note there.
  | Message | When | Holds |
  |---|---|---|
  | `note.created` | a note arrives | words, recording, time, place, phone |
  | `note.updated` | a ring note gets its place later | the note, without the recording |
  | `health.samples` | a health sync | up to 500 samples |
  | `location.points` | a location sync | up to 500 points |
  | `webhook.test` | you press *Send a test* | a hello |

Removing a webhook deletes its secret and its send history; this can't be undone. Your notes stay in Relay.

Non-goals: sending from the phone directly, writing into a database without a webhook, choosing your own format, sending to a person's AI (the MCP server plan), and end-to-end encryption.

It builds on the Relay app first version, which is now published.

## What the build needs

- **Cloudflare token for the queues**: Ready, `CLOUDFLARE_API_TOKEN` is in `.env`, and the account already runs queues.
- **A test address for your database**: Ready, the build makes a throwaway receiver to test against. Your real database can come later.

## Capabilities

### New Capabilities
- `relay-webhooks`: owner-managed outbound webhooks for Relay notes, health and location, the versioned signed format, queued delivery with retries, test sends and resending from a date.

### Modified Capabilities
None. `relay-notes` and `relay-sync` come from `relay-app-first-version`; this change adds a send after their stores and does not change what they promise.

## Impact

- New: `app/worker/apps/relay/webhooks/` (management routes, payload builder, signing, sender), a migration in `schema/migrations/` for `relay_outbox` (filled by triggers on the first version's tables), `relay_webhooks` and `relay_webhook_attempts`, seed rows in `schema/seed.sql`, a Webhooks section in `app/src/apps/relay/`, the website page `site/src/content/docs/connections/your-database.md`, the schema `site/public/webhooks/v1.schema.json` and the example receiver `site/public/webhooks/receiver.mjs`; `standardwebhooks` as a dev dependency of `app/` for tests.
- Changed: `AGENTS.md`'s Relay section (health and location also go to webhooks the owner ticks), the `pebble`, `notes`, `health` and `locations` handlers from `relay-app-first-version` (one wake-up call after they store), `app/worker/apps/index.ts` and `app/worker/index.ts` (a generic hook so a mini app can own a queue consumer and a sweep), `app/wrangler.jsonc` (queue producer and consumer, production and staging), `site/src/content/docs/connections/index.md` and `site/sidebar.mjs` (the *Coming* note becomes a link), and the generated API page `site/src/content/docs/api/reference.md`.
- Cloudflare: queues `relay-webhooks` and `relay-webhooks-staging`.
- Builds on: `relay-app-first-version`, published to `main`.

## Decision log

- **2026-11-05** — Asked which data a webhook sends → chose notes always, with health and location ticked for each webhook.
- **2026-11-05** — Asked what happens to earlier data when a webhook is added → chose new data only, plus a *Send past data from a date* button.
- **2026-11-05** — Asked how a ring note's recording reaches the database → chose inside the message, as base64.
- **2026-11-05** — Asked where the webhook sends from, given that Relay is offline by default → chose phone → Relay server → your database; only the server sends, and only data the server holds.
- **2026-11-05** — Asked whether end-to-end encryption changes how webhooks send → chose no encryption: Relay goes fully open source, people who want protection host it themselves, and the server keeps building and sending each message.
- **2026-11-05** — Assumed: the format follows Standard Webhooks (`webhook-id`, `webhook-timestamp`, `webhook-signature`), because receivers in most languages can check it with a ready library.
- **2026-11-05** — Assumed: delivery runs on a Cloudflare Queue with backoff for about 24 hours, then the webhook shows as failing with a *Try again now* button, because a queue survives Worker restarts and the account already uses queues.
- **2026-11-05** — Assumed: every stored row also goes into a send list in the same database write, and each webhook keeps its place in that list, because the first version's saved code stores each item in one write, and a separate send record could be lost between two writes.
- **2026-11-05** — Assumed: health and location go as batches of up to 500 rows per message, not one message per row, because a sync sends hundreds of rows at once.
- **2026-11-05** — Assumed: each webhook gets messages in order, but a retry after a lost answer can repeat one, so every item has a stable id and a receiver upserts.
- **2026-11-05** — Assumed: only the owner, signed in as a person, manages webhooks; device keys can't, because a device key only sends data.
- **2026-11-05** — Assumed: a webhook address must be `https` and can't point at a private network, `localhost` or Relay's own site, because the server would otherwise call addresses for an attacker.
- **2026-11-05** — Assumed: the format page lives on the Relay website (`site/`), with its schema and example receiver as files there, because the website is public and relay-app is archived now that the whole project is one public repository.
- **2026-11-05** — Assumed: the webhooks section sits at the bottom of the Relay page, below the notes, because the page's main job is the timeline and you set up a webhook once.
- **2026-11-05** — Assumed: a note sent to the server later, when sending is turned on with earlier notes, goes out as `note.created` at that time, because the server sees it as new then.
- **2026-11-05** — Assumed: the seed webhook is paused and points at `example.com`, because a preview must never send made-up data to an outside address.
- **2026-11-05** — Assumed: the tables have a few columns the design did not name: `tries`, `next_try_at`, `backfill_seq` and `last_sent_at` on `relay_webhooks`, and `logged_at` on `relay_outbox`. They count the retries, stop a second retry chain, show *Sending past data*, and keep a message's `timestamp` the same on each retry.
- **2026-11-05** — Assumed: *New secret* asks for a confirmation first, because the old secret stops working at once.
- **2026-11-05** — Assumed: the sweep's manual trigger is `POST webhooks/sweep`, owner-only and refused on production, because the rule for timed jobs asks for a trigger that only staging answers.
- **2026-11-05** — Assumed: the local environment binds its own queue, `relay-webhooks-local`, and the queue router drops a `-local` end as it drops `-staging`, so `wrangler dev` runs the same code.
- **2026-11-05** — Assumed: the sender checks the address again before each send, but without the site's own host, because the queue has no request to read it from and the private address can't be written into the code.
- **2026-11-05** — Assumed: a run stops after 20 messages and queues itself again, and a ring note waits up to 2 minutes for its recording, so one run stays short and a note never goes out before its sound.
- **2026-11-05** — Assumed: the secret in the *Secret, shown once* picture is covered with dots, because the repository is public and its check does not read text in pictures. The prototype made that secret in the browser, so no server holds it.
- **2026-11-05** — Assumed: the *Try it* lines keep the preview's address, because the review page needs one link, the preview is behind a login, and the repository already names the site's address.
- **2026-11-05** — Built tasks 1.1 to 7.1. A second look found the sender kept an old lease time, so the send position never moved outside the tests; fixed, with a test whose clock moves. Saved for the preview check (7.2), merged with the AI connector change.
- **2026-11-05** — The preview check found a second lease slip: a run that stopped early, because a retry was already planned, gave its lease back with the old time, so the planned retry found the lease taken and was dropped. Fixed, with a test.
- **2026-11-05** — The preview check passed on the staging Worker: a test answered 204; a typed note and a health sample arrived; with the receiver stopped, six notes waited and then arrived in order after a retry; *Send past data* from a week ago sent the earlier notes and samples; *Remove* cleared the webhook. The receiver was stopped for about two minutes, not five, so the 2-minute retry carried the notes.
- **2026-11-05** — Archived for publishing, with the spec added to `openspec/specs/relay-webhooks/`.
