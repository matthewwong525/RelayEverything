# Proposal: Add a kind of data once, and never break a webhook

**Status:** in-progress
**Branch:** juicy-ladybug
**Open questions:** none

## Why

In alpha, Relay Everything gets new kinds of data often: files, photos, chats, then texting. Today each new kind touches many files, and nothing catches a missed one, such as a webhook tick with no docs page. A receiver can also break when a new kind of message arrives that it does not know. This change makes adding a kind one step, checked, and safe for the receiver.

## What Changes

- **Each kind of data is listed once, with all its parts.** Notes, health, places and calendar each have one entry: the tick on the webhook form, its messages, its web API route, its AI tool and its docs page. Adding a kind means adding one entry. A check fails when a kind misses a part. Files, photos and chats show as missing for now; a later plan fills them in.
  | Kind | Tick | Messages | API | AI tool | Docs |
  | --- | --- | --- | --- | --- | --- |
  | Notes | Always on | Yes | Yes | Yes | Yes |
  | Health | Yes | Yes | Yes | Yes | Yes |
  | Places | Yes | Yes | Yes | Yes | Yes |
  | Calendar | Yes | Yes | Yes | Yes | Yes |
  | Files, photos, chats | Missing | Missing | Some | Some | Some |
- **A new kind is off until you tick it.** A webhook you made before gets nothing new. The add form and the card take their ticks from the list, so a new kind shows up there by itself.
- **A new message never breaks your database.** The website tells receivers to answer *OK* to a message they don't know, to keep fields they don't know, and to accept a new value, such as a new health type. The public schema lets unknown fields through. The example receiver keeps a message it doesn't know as a raw row, so nothing is lost.
  ```mermaid
  flowchart TD
    M["A message arrives"] --> K{"Known type?"}
    K -->|"Yes"| S["Save it by its id"]
    K -->|"No"| R["Keep it as a raw row"]
    S --> A["Answer OK"]
    R --> A
  ```
- **The website says the format can still change.** Until the public release, version 1 can change in any way, and the *Your own database* page says so. On release day, version 1 becomes the first public format.

Non-goals: webhook versions, an *Upgrade* button, end dates for old versions and a public changelog (parked until just before the public release); webhooks for files, photos and chats (a later plan).

## What the build needs

- **Nothing.**

## Decision log

- **2026-11-07** — Asked (in the research chat) whether to plan a process for webhook changes → chose yes, in five parts: a list of kinds, receivers that ignore what they don't know, a version per webhook with *Upgrade*, old versions kept for a time, and a changelog.
- **2026-11-07** — Asked how this plan treats *Send from the phone straight to your own webhook*, which adds a message type → chose to keep going here; whichever publishes second adds its message to the list of kinds.
- **2026-11-07** — Asked whether webhooks for files, photos and chats come in this plan → chose a separate plan for every kind; this plan marks them as missing.
- **2026-11-07** — Asked what happens when an old version ends and a webhook is still on it → chose the webhook pauses, and what waits is sent after the upgrade. This applies to the parked versions part.
- **2026-11-07** — Asked what to build in alpha → chose the list of kinds and the ignore-unknown rule now. Versions, *Upgrade*, end dates and the changelog wait until just before the public release, when version 1 freezes as the first public format. How long an old version stays (6 or 12 months) is decided then.
- **2026-11-07** — Assumed: calendar is a kind in the list, because *Your phone's calendar and more health* is published.
- **2026-11-07** — Assumed: the card and the form get the ticks from the server, so the web page holds no second copy of the list.
- **2026-11-07** — Assumed: no screen picture, because the add form and the card look the same as today; only where their ticks come from changes.
- **2026-11-07** — Assumed: the rules for adding a kind go on a new wiki page, because no page owns them and the next kind needs them.
- **2026-11-07** — Assumed: *Send from the phone straight to your own webhook* published first, so its `note.file` message joins the list under notes, beside `note.created` and `note.updated`.
- **2026-11-07** — Assumed: the example receiver also saves `calendar.events` in a `calendar_events` table, because the check needs a receiver branch for each message type. It is about 80 lines, not 75.
- **2026-11-07** — Assumed: the web page shows *Add a webhook* only after the list of kinds loads, because the form takes its ticks from it. When the list fails, *Try again* loads it. A shared server not yet deployed again answers no `kinds`, so the page shows no form until it is, and the rest of the page still works.
- **2026-11-07** — Assumed: the docs pages for files, photos and chats are `api/files`, `app/your-notes` and `connections/claude-code`; files and photos list their web API route and AI tool as missing too.
- **2026-11-07** — Assumed: the check that a kind has every part is a function in `kinds.test.ts`, and the test that it fails on a missing docs page runs every time, not once by hand.
- **2026-11-07** — Check: the `Webhooks.test.tsx` case *adds a webhook with the kinds ticked* now loads the list before it goes offline, because the form's ticks come from the list. What it checks is the same.
- **2026-11-07** — Assumed: task 1.1's check passed: `log.ts` names `calendar`, and `npm test` in `app/` failed only two page tests that ran out of time under load and passed alone (`Welcome.test.tsx`, `Drag.test.tsx`).
- **2026-11-07** — Built inside /ship: list of kinds, ignore-unknown schema and receiver, ticks from the server, docs and wiki page; the review found nothing to fix. Full `npm test` failed only on two untouched page tests that time out under load (Inbox week rows, Access welcome) and pass alone; the rest of the chain passed. Specs reconciled; saved for the preview check (task 6.2).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-webhooks`: one registry of data kinds checked by a test; new kinds off until ticked; receivers may ignore what they don't know; the published schema accepts unknown fields; version 1 may change in place until the public release.

## Impact

- **Server** (`app/worker/apps/relay/`): a new `kinds.ts` registry and `kinds.test.ts`; `webhooks/send.ts`, `webhooks/log.ts` and `webhooks/routes.ts` read the registry; `GET webhooks` also answers the tickable kinds; `webhooks/format.ts` publishes a schema that accepts unknown fields.
- **Web page** (`app/src/apps/relay/Webhooks.tsx`, `read.ts`): ticks and kind names from the server.
- **Website** (`site/`): `connections/your-database.md` gains *When the format changes*; `public/webhooks/v1.schema.json` regenerated by `npm run relay:api-doc`; `public/webhooks/receiver.mjs` keeps unknown messages.
- **Wiki**: a new `wiki/relay-webhook-changes.md`, linked from `wiki/README.md`.
- **Overlaps** `phone-sends-to-your-webhook` (its `note.file` type joins the registry).
