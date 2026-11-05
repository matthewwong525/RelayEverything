# Design

## Context

This change builds on `relay-app-first-version` (see its `design.md`), published to `main`. That change adds the mini app `relay`: `app/worker/apps/relay/` with `pebble`, `notes`, `health`, `locations`, `timeline`, `summary` and audio routes, D1 tables `relay_devices`, `relay_notes`, `relay_health`, `relay_locations`, audio in R2 `RELAY_BUCKET` at `notes/<id>.m4a`, the page `app/src/apps/relay/`, and per-device Access service tokens limited to the device routes. The plan `relay-offline-by-default` (another chat) keeps notes on the phone until the person turns on sending to Relay's server. So webhooks see only what the server stores.

The core Worker (`app/worker/index.ts`) has `fetch` and a production-only 15-minute `scheduled` handler, and no `queue` handler. Mini app routes are exact `"METHOD route"` keys (`app/worker/apps/index.ts`), with no path parameters. Handlers get `(request, env, call)` and no `ExecutionContext`. The account already runs Cloudflare Queues (`wong-queue`), so the plan supports them.

## Goals / Non-Goals

**Goals:** server-side fan-out after each store, a documented and versioned signed format, retries that survive restarts, owner-only management on the Relay page, and resending from a date.

**Non-Goals:** phone-side sending, per-webhook custom formats or field mapping, direct database drivers, multiple users, and ordering guarantees.

## Decisions

### Delivery: the data is the outbox, and each webhook keeps its place

The first version stores each note, sample batch and point batch with one `INSERT … RETURNING` on a D1 session, not a shared batch, and `pebble` puts the recording in R2 after its insert (deleting the note if R2 fails). So this change never asks a handler to write delivery rows. Instead:

- **A send log, filled by triggers.** `relay_outbox(seq INTEGER PRIMARY KEY AUTOINCREMENT, kind, ref, at)` gets one row from SQLite triggers in the same statement as the data. The triggers are: `AFTER INSERT ON relay_notes` → `note.created`; `AFTER UPDATE OF lat ON relay_notes WHEN old.lat IS NULL AND new.lat IS NOT NULL` → `note.updated`; `AFTER INSERT ON relay_health` → `health`; `AFTER INSERT ON relay_locations` → `location`. `at` is the item's own time (`recorded_at`, `start_at`, `at`). A stored row can never miss its log entry, because both commit together or neither does. The migration also fills the log from rows already stored, in time order, so *Send past data* reaches them.
- **Each webhook has a cursor.** `relay_webhooks.sent_seq` is the last log entry the address accepted. The sender reads entries after it, for the kinds the webhook takes. It groups consecutive `health` (or `location`) entries into one message of up to 500, and sends each note alone. It saves the group's last entry as `pending_seq` before the first try, so every retry sends the identical group with the identical `webhook-id`, `msg_<webhook>_<first seq>_<last seq>`; a receiver that drops repeated ids never drops new rows. It moves `sent_seq` to `pending_seq` only after a 2xx. So a webhook gets everything, in order, however long it was down.
- **The queue only says "look now."** After a store, the handler sends `{ webhook }` to `RELAY_WEBHOOKS` for each active webhook. A lost message costs only time: the 15-minute production sweep sends the same message for every webhook whose cursor is behind the log.
- **One sender per webhook at a time.** A consumer first takes a 2-minute lease (`UPDATE relay_webhooks SET lease_until = ? WHERE id = ? AND (lease_until IS NULL OR lease_until < ?)`). Without the lease, it acks and stops, because the holder is already sending. The holder sends until the cursor reaches the log's end, at most 20 messages per run, then re-queues itself. Before it gives up the lease, it checks the log once more, so nothing that arrived during the run waits for the sweep.
- **Retries.** A non-2xx, a timeout (15 s) or a redirect leaves the cursor where it is. The consumer records the attempt and calls `message.retry({ delaySeconds })` on the schedule 30 s, 2 m, 10 m, 30 m, 1 h, 2 h, 4 h, 6 h, 8 h (about 22 h). After the last try, it sets `failing_since` and stops retrying. The page shows *Failing* with the last answer and how many entries wait. *Try again now* clears it and sends from the cursor, so nothing is lost even after days.
- **A recording not yet saved.** If a note has `audio_key` but R2 has no object yet, and the note is under 2 minutes old, the run stops there and retries in 30 s. A log entry whose note is gone (deleted by `pebble` after an R2 failure) is skipped.
- **A short attempt log for the page.** `relay_webhook_attempts(webhook_id, at, first_seq, last_seq, type, status, ms, error)` keeps the last 30 days. The sweep prunes it.
- Queues `relay-webhooks` (production) and `relay-webhooks-staging`: producer binding `RELAY_WEBHOOKS`, consumer `max_batch_size: 10`, `max_retries: 10`. There is no dead-letter queue: the cursor holds the state, and the sweep catches a crashed consumer.
- *Alternatives:* (1) One delivery row per send, written by each handler. This was the first draft. A crash between the data insert and the delivery insert loses a send, and the first version's handlers don't share a batch. (2) Sending inline in the handler: Pebble's app and phone syncs would wait on the person's database. (3) A Durable Object per webhook, with alarms: it serializes on its own, but needs a new class and migration in this Worker. A lease on a queue does the same with less.

### Core hook: apps may export a queue consumer and a sweep

`app/worker/apps/index.ts` gains `handleAppQueue(batch, env)` and `handleAppSchedule(env)`. An app's `api.ts` may export `queues: Map<string, consumer>`, keyed by queue name without the `-staging` suffix, and `scheduled`. Each gets the same memory-free `AppEnv` as a route. `app/worker/index.ts` adds a `queue` handler that calls `handleAppQueue`, and calls `handleAppSchedule` after `refreshOnSchedule`. This hook is generic and small, so the core never imports `relay` by name. Tests cover an unknown queue name (ack, log) and the memory bindings being absent.

### Tables (one migration)

- `relay_outbox(seq INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT CHECK (kind IN ('note.created','note.updated','health','location')), ref TEXT NOT NULL, at INTEGER NOT NULL)`, an index on `(at)`, and the four triggers above. It is never pruned: about 40 bytes a row, roughly 30 MB a year.
- `relay_webhooks(id, name, url, secret, kinds TEXT /* JSON: ["notes","health","locations"] */, active INTEGER, sent_seq INTEGER, pending_seq INTEGER, lease_until INTEGER, failing_since INTEGER, last_status INTEGER, last_error TEXT, created_at)`. A new webhook starts with `sent_seq` at the log's current end.
- `relay_webhook_attempts(...)` as above, with `ON DELETE CASCADE` from its webhook.
- Seed: one example webhook at `https://example.com/relay` with made-up attempts. Seeded notes, samples and points fill the log through the triggers.

### Format v1: Standard Webhooks

- Headers: `webhook-id` (`msg_<webhook>_<first seq>_<last seq>`, the same on every retry), `webhook-timestamp` (Unix seconds), `webhook-signature: v1,<base64 HMAC-SHA256 of "{id}.{timestamp}.{body}">`, and `content-type: application/json`. Secret: `whsec_` + base64 of 32 random bytes.
- Body: `{ "version": 1, "type": "...", "timestamp": "<ISO 8601 UTC>", "data": { ... } }`.
  - `note.created`: `data.note = { id, source: "ring"|"typed", text, recorded_at, created_at, device: { id, name }, place: { lat, lon, accuracy, name, from: "phone"|"history" } | null, audio: { content_type: "audio/mp4", base64 } | null }`. Times are ISO 8601 UTC, converted from the stored Unix milliseconds. Note ids are UUID strings; sample and point ids are integers, unique within this Relay.
  - `note.updated`: the same `note`, without the `audio` key. It is sent when a later location batch fills a ring note's place.
  - `health.samples`: `data.samples = [{ id, device, type, start, end, value, unit, source }]`, up to 500 per message, only rows not sent before.
  - `location.points`: `data.points = [{ id, device, at, lat, lon, accuracy, place }]`, also up to 500 per message.
  - `webhook.test`: `data = { webhook: { id, name } }`.
- One zod schema in `app/worker/apps/relay/webhooks/format.ts` is the source. `site/public/webhooks/v1.schema.json` is generated from it with `z.toJSONSchema`, and an `app/` test fails when the committed file differs. So the public schema never drifts.
- The website page `site/src/content/docs/connections/your-database.md` (by [the website rules](../../../wiki/relay-website.md#add-or-change-a-page)): how to add a webhook, the envelope, each type with an example, signing, retries and upsert advice (each webhook gets messages in order, but a retry can repeat one, so upsert by id), a 16 MB body limit, Postgres `CREATE TABLE`s, and the receiver. `connections/index.md` swaps its *Coming* note for a link, and `sidebar.mjs` drops the *Soon* badge. The receiver, `site/public/webhooks/receiver.mjs`, is about 50 lines of Node with no packages: it checks the signature with `node:crypto` and upserts into `node:sqlite`, so it runs with no database server. The page shows it and links the file. An `app/` test runs it against bodies signed by the real sender. A second test checks that `standardwebhooks` verifies the same bodies, which proves the ready libraries work.
- The owner routes are described in the contract, so `npm run relay:api-doc` adds them to the generated Routes page, marked as called by a signed-in person.
- *Alternative:* a Relay-specific signature like Pebble's. It was rejected, because Standard Webhooks has checked libraries in most languages.

### Routes (owner only)

All routes are described with the shared contract, with `allowed: identity => identity?.kind === "user"`, so a device token is refused even if the device-route limit changes. They use exact paths and carry ids in the body:

| Route | Does |
|---|---|
| `GET webhooks` | list, with each webhook's state, how many entries wait, last answer, next try and 20 recent attempts |
| `POST webhooks` | add `{ name, url, kinds }`; returns the secret once |
| `POST webhooks/update` | `{ id, name?, url?, kinds?, active? }` (pause and resume) |
| `POST webhooks/remove` | `{ id }`; cascades its attempts |
| `POST webhooks/secret` | `{ id }`; replaces the secret and returns it once |
| `POST webhooks/test` | `{ id }`; sends `webhook.test` inline and returns `{ status, ms, error? }` |
| `POST webhooks/resend` | `{ id, since }`; starts a backfill |
| `POST webhooks/retry` | `{ id }`; clears `failing_since` and queues a run from the cursor |

The list and other responses never include `secret`.

### Address check

`checkAddress(url, siteHost)`: the scheme must be `https:`. The URL has no user info. The host is not `localhost`, `*.localhost`, `*.local`, `*.internal`, or the site's own host or `*.workers.dev` preview hosts of this project. An IP literal is not in 0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12, 192.168/16, ::1, fc00::/7 or fe80::/10. The check runs on add, on update, and again before each send. Redirects are not followed.

### Backfill

`webhooks/resend { id, since }` clears `pending_seq`, moves `sent_seq` back to just before the first log entry with `at >= since`, then queues a run. The webhook then gets everything logged after that entry, in log order. That can include a few items older than `since` that were stored late, which is harmless because receivers upsert. A second resend just moves the cursor again.

### Hooks into the first version's handlers

The triggers fill the log, so the handlers change only to queue a run: `pebble` (after the R2 put), `notes`, `health` and `locations` call `wake(env)` when they added at least one row, and `locations` also when `placeRingNotes` filled any. `wake` sends `{ webhook }` for each active webhook and swallows queue errors, which the sweep covers. Pebble test events and duplicates add nothing, so they wake nothing.

## UX

### Use-case brief

The owner of a Relay server wants his notes, and optionally his health and places, copied into a database he runs. Done means a new note shows up as a row there within a minute. He sets up a webhook once, through the Relay page on a computer (a rare task: one or two webhooks ever). After that, he checks the page now and then when something seems missing. The common case is a working webhook. The edge cases are a failing address, a lost secret and catching up past data. This mirrors the site's Access page: a list of cards with ghost actions, and dialogs to add.

### Flow

Relay page → *Add a webhook* → name, address, ticks → *Add* → copy the secret → *Done* → *Send a test* shows *200 in 180 ms*. Branches: *Send past data* → pick a date → *Send*; a failing card → *Try again now*; *Remove* → confirm.

### Hierarchy

- Webhooks section: below the notes, with no primary action; *Add a webhook* is a ghost button beside the heading, because the page's main job is the timeline.
- Add dialog: *Add* is primary.
- Secret dialog: *Done* is primary, and the secret field is selected with a copy button.
- Each card: the status tag is the first thing you see (*Working*, *Paused*, *Failing*, *Sending past data*). Its actions are ghost buttons: *Send a test*, *Send past data* (or *Try again now* when failing), *New secret*, *Pause*, *Remove*.

Components: `Card`, `Button`, `Badge`, `Dialog`, `Input`, `Checkbox` and `AlertDialog` (for *Remove*) from `app/src/components/ui/`, added with shadcn where missing.

### Review

[review.html](review.html): What Changes item 2 shows the add dialog, and item 3 shows the webhooks section and the secret dialog, as pictures of the prototype on the change's preview address. The build starts from `.scratch/relay-webhooks-prototype.diff`.

## Risks / Trade-offs

- [Health and location leave Cloudflare] → They are off by default for each webhook, and the add dialog says they are sensitive. Only the owner manages webhooks.
- [Secrets are stored in D1 in plain text, because signing needs them] → They are in the owner's own Cloudflare account beside the data they protect, are never returned after creation, and can be replaced in one click.
- [DNS that points a public name at a private address] → Cloudflare Workers' `fetch` can't reach private networks, and the host check stops the obvious cases. Redirects are refused.
- [A 10 MB recording becomes a 13 MB body] → Ring notes are short (16 kHz, about 100 KB a minute). The format doc says to accept bodies up to 16 MB.
- [Repeated messages] → A retry after a lost answer sends the same group again. Stable ids make upserts safe, and the doc says so.
- [One slow address holds up only itself] → Each webhook has its own cursor and lease, so a failing one never delays another or the stores.
- [Triggers are new to this project's migrations] → Triggers are standard SQLite and supported by D1. The migration test runs them on the check runner's SQLite.
- [Queue retry limits] → The longest wait used is 8 h, under the 12 h maximum. A crashed consumer or a lost wake-up is caught by the sweep, which runs on production only. Staging previews rely on the wake-ups and *Try again now*.

## Migration Plan

Deploy order follows the normal publish: the migration first, then the Worker with its queue bindings. Create the queues before the deploy (task 1.1). Rollback: remove the queue consumer from `wrangler.jsonc`. Existing data is untouched, and the new tables can stay.
