# Design: private data straight to your own webhook

## Context

See proposal.md, Why. Since #72 the phone has one place: `Settings.place` is `server` or `webhook`, and `Sender.api` gives one `Outbound` client for it. The outbox already stores a `destination` per row (`relay-server` or `webhook`), and `Store.enqueue` takes the current one from the `outbox.destination` state key in the same statement. `flush` walks every waiting row and stops at the first one for another destination. Photos wait apart, in their own queue, and go through the same client after the outbox. `WebhookClient` already builds every v1 message the private routes need (`health.samples`, `location.points`, `calendar.events`, `photo.created`), signs them, and records `webhook.problem`.

## Goals / Non-Goals

**Goals:** two clients at once in server mode, each with its own ordered queue; no private row ever sent through `RelayApi` while the choice is on.

**Non-goals:** a server change; a per-kind destination; more than one phone-held webhook.

## Decisions

### One new setting, read as a private place

`Settings` gains `privateTo` (`SendPlace`, default `server`, saved as `privateTo`; old settings read `server`). A derived `privatePlace` is `webhook` when `place == webhook`, else `privateTo`. Only `privatePlace` is read elsewhere, so whole-webhook mode needs no special case. `privateTo` survives *Sign out*, so signing in again keeps the person's choice; a privacy choice that silently resets breaks its promise.

*Alternative:* a third `SendPlace` value such as `serverAndWebhook`. Rejected: every `switch` on `place` would need a case, and the Account row and sign-in already read `place` as "where notes go".

### The store routes by kind at enqueue

A second state key, `outbox.private`, holds the private destination. `enqueue` picks `outbox.private` for `health`, `locations` and `calendar`, and `outbox.destination` for every other route, in the same `INSERT … SELECT`, so an upload never takes a stale place. `moveOutbox(notes, private)` sets both keys and updates each group's rows in one transaction. It drops the calendar's sent list when the private destination changes (today: when the one destination changes), so the new place gets the whole window. The id fill for health and points stays as it is.

The photo queue has no destination column: a photo is sent by whichever client the round gives the photo step, so it needs none.

### `flush` sends only its own destination

`flush` lists `store.outbox(destination: api.destination)` in place of every row. It still reads each row again before sending and stops when the row is gone or moved, which keeps today's guard against a change of place in the middle of a round. Rows for the other destination are no longer a stop: they belong to the other flush.

*Alternative:* one flush with two clients, picking per row. Rejected: one failing place would stop the other, against the spec, and the order guarantee is per place anyway.

### `Sender.privateApi`

`Sender.privateApi(settings, connection, webhook, installId)` returns the private client: the same as `api` when `privatePlace == place`; the `WebhookClient` when `privatePlace == webhook` and the webhook and install id are there; else null. Null means private rows wait. It never returns `RelayApi` while `privateTo == webhook`: that is the promise, and a test pins it.

### Two flushes per round

`Controller._sync` and `backgroundRound` flush `api`, then flush `privateApi` when its destination differs, then send photos through `privateApi`. Reading health, the calendar and points is unchanged: rows queue and wait if the private client is null. `keepGoing` checks both `place` and `privatePlace`. `SyncStatus` shows the notes side, as the home screen's line is about notes; the webhook side shows as `webhookProblem` on the Account page. `backgroundRound` returns true only when both flushes and photos finished. The notes pull still runs only after the notes flush emptied.

`load()` keeps turning sending off when the notes place is not ready. A missing webhook with `privateTo == webhook` leaves sending on and sets `Relay.privateWebhookMissing`, which the Account page shows as *Set your webhook again*.

### UI reuses the webhook screen

`account.dart`'s signed-in list gets a `Group` *Health, places, calendar and photos* between *Connections* and the page link, with a `RadioGroup<SendPlace>` like the location mode's. Picking *Only my own webhook* with no webhook kept opens `connect.dart`'s webhook form in a private mode: *Save* keeps the webhook and calls `setPrivatePlace(SendPlace.webhook)`, and does not start whole-webhook sending or ask about earlier notes. Leaving the form changes nothing. With the webhook picked, the group shows its host, *Send a test* and `problemLine`, as the webhook-mode Account page does. The folder pages' sent lines read *Sent to your webhook 14:05* when `privatePlace == webhook`.

## UX

### Use-case brief

A signed-in person who syncs notes but keeps their own database for personal data. They set this once, in the Account page they already visit to see AI apps and webhooks, and rarely touch it again. The common case: they already run a receiver for the server's webhooks and paste its address. The edge cases: no webhook kept, the receiver down, and the webhook lost after a restore. Mirrors the webhook-mode Account page from #72.

### Flow

Settings → Account row → *Only my own webhook* → (no webhook kept) webhook form: address, copy secret, *Send a test*, *Save* → back on the Account page with the choice picked. Switching back is one tap on *Relay Everything*, with no question, as switching back sends nothing new outside our server.

### Hierarchy

On the Account page the email stays first and *Sign out* stays last in red. The new group adds no filled button: the picked row's check is its only mark, so *New note* stays the screen's one bright thing. *Send a test* is a quiet text button.

### Review

[review.html](review.html). What Changes items 1, 2 and 3 sketch the group, the picked state and the webhook-gone state.

### Components

Existing: `Group`, `RadioGroup` / `RadioListTile` (as in the location mode), `ListTile`, `quietButton`, `problemLine`, and `connect.dart`'s webhook form. Nothing new.

## Risks / Trade-offs

- [A private row sent to the server by a bug] → `privateApi` never returns `RelayApi` with `privateTo == webhook`; controller and background tests assert no `health`, `locations`, `calendar` or photo request reaches the fake server with the choice on.
- [Two flushes make a background wake longer on iPhone (about 25 s)] → private rows were already in the same flush; only the webhook's network wait is new. The order is notes first, so a slow receiver delays only private data.
- [A downgraded app moves every row to its one destination at load] → that sends waiting private data to the server. Builds go forward only through TestFlight and the store; noted, not handled.
- [Private data grows on the phone while the webhook is lost] → the folders already show how many wait, and the Account page names the cause.

## Migration Plan

No server change and no table change. Old settings read `privateTo: server`; a missing `outbox.private` key reads as `outbox.destination`, so an updated phone behaves as today until the person picks the webhook.
