# One path to your webhook: signed in, through Relay Everything; with no account, straight from the phone

**Status:** ready-to-ship
**Branch:** loved-turtle
**Open questions:** none

## Why

A signed-in phone can send in two directions at once: notes to Relay Everything, and health, places, calendar and photos straight to your own webhook. That split lost notes. Matthew signed in around 9 November with *Only to my own webhook* on. His webhook got health, places, calendar and photos from the phone, but no notes, because no webhook was added on his Relay Everything page. About 25 notes never reached it, and nothing on the phone showed it.

One path for each way of using the app removes that trap. With an account, everything goes to Relay Everything, and Relay Everything sends it on to the webhooks you add on your page. With no account, everything stays on the phone or goes straight from the phone to your own webhook.

## What Changes

- **A signed-in phone sends everything to Relay Everything, and never to a webhook itself.** Notes, health, places, calendar and photos go to Relay Everything. Your page's webhooks get each kind you tick for them. With no account, the phone sends everything straight to your own webhook, as today.
  ```mermaid
  flowchart TD
    P1["Phone, signed in"] -->|"everything"| R["Relay Everything"]
    R -->|"what you tick"| W1["Your webhooks"]
    P2["Phone, no account"] -->|"everything"| W2["Your own webhook"]
  ```
- **The *Only to my own webhook* switch goes away.** *Webhooks* on the Account page lists your webhooks and opens your page to add or change one. Its first line now says a webhook gets your notes and what else you tick for it.
  ```picture
  Before: pictures/before-webhooks.png
  After: pictures/after-webhooks.png
  ```
- **A phone that has the switch on today moves to Relay Everything, and says so once.** After the update, its health, places, calendar and photos go to Relay Everything, with what was waiting on the phone. The next time you open the app, one message says so, and *Open Webhooks* takes you there. To keep getting them at your webhook, add it on your page and tick them. Your phone keeps the webhook's address and secret, for a later *Sign out*. It can't be undone: what goes to Relay Everything after the update stays there until you delete it.
  ```picture
  After: pictures/after-moved-message.png
  ```
- **Signing in from your own webhook says that everything moves.** On the webhook Account page, *Sign in to Relay Everything* no longer says your private data stays on your webhook. It says everything then goes through Relay Everything, and to add your webhook on your page. The *Sign in* screen says the same, and the message after sign-in says to add the webhook to keep getting everything.
  ```picture
  Before: pictures/before-account-webhook.png
  After: pictures/after-account-webhook.png
  ```
  ```picture
  Before: pictures/before-sign-in-from-webhook.png
  After: pictures/after-sign-in-from-webhook.png
  ```
- **The folders say *Sent* again, never *Sent to your webhook*, while signed in.** Health, Location, Calendar and Photos show when data last reached Relay Everything.
- **The website and the project's rules say one path.** The Settings, Health, Location, Calendar, Photos, privacy and *Your own database* pages lose *Only to my own webhook*, and say: signed in, everything goes through Relay Everything; to keep data off our server, use the app with no account and your own webhook.

**Works with the recordings plan.** The plan *Recordings go in a note like files* changes what a webhook gets for a voice note: the spoken words go as the transcript of a recording in the note's file list, and the sound goes as a file. This plan keeps two paths to a webhook, from Relay Everything and, with no account, from the phone. Both must carry recordings as files with their transcripts. Whichever plan lands second follows the other.

**Works with the delete plan.** The plan *Delete like Apple Notes* keeps *note deleted* when a note goes to *Recently Deleted*, and adds a *note recovered* message. Both messages must go on both paths: from Relay Everything to your webhooks, and from the phone with no account to your own webhook. Whichever plan lands second follows the other.

Non-goals: no server change; the phone does not add its webhook to your page for you, because a phone key can't change account settings; no change to the no-account webhook mode.

After it ships, Matthew adds the WongOS webhook on his Relay Everything page, ticks health, places, calendar and photos, and sends past data from 9 November, so the 25 notes reach WongOS. That is a step on the page, not part of the build.

## What the build needs

- **Nothing.** The server already sends every kind to the webhooks ticked for it, and can send past data to a new webhook.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-phone-webhook`: the private-data choice goes; a signed-in phone sends to no webhook itself, and a phone that had the choice moves to Relay Everything with a one-time message.
- `relay-sending`: signed in, all data goes to Relay Everything; no second place.
- `relay-settings`: *Webhooks* loses *Only to my own webhook*; the account card's private-data scenario goes.
- `relay-photos`: photos go where notes go.
- `relay-health-nights-workouts`: nights and workouts go where health goes, which is where notes go.

## Impact

- `mobile/lib/data/settings.dart`: `privateTo` and `privatePlace` go; `Settings.decode` reads an old `privateTo: webhook` as the one-time move and sets a flag for the message.
- `mobile/lib/data/store.dart`: the `outbox.private` key and its routing go; `moveOutbox` takes one destination; an update moves waiting `health`, `locations` and `calendar` rows to `relay-server` and drops the calendar's sent list.
- `mobile/lib/data/sender.dart`: `privateApi` goes. `mobile/lib/data/outbox.dart`: `flush` loses its `private` split.
- `mobile/lib/controller.dart`, `mobile/lib/sync/background.dart`: one flush per round, photos through the one client; `setPrivatePlace`, `privateWebhookMissing` and `startSending(privateTo:)` go; the one-time message flag.
- `mobile/lib/relay.dart`, `mobile/lib/web/web_relay.dart`: the same members go from the interface.
- `mobile/lib/screens/webhooks.dart`, `account.dart`, `connect.dart` (`privateOnly` and the `signInOnly` words), `folder.dart` (`keepWebhook`, `_toWebhook`), `connect_ai.dart`, `email_notes.dart`, `home.dart` (the one-time message).
- Tests: `mobile/test/screens_test.dart`, `controller_test.dart`, `store_test.dart`, `sync_test.dart`, `health_test.dart`, `narrow_test.dart`, `web_settings_test.dart`; `mobile/device-check/flows/settings.yaml` if it taps the switch.
- Docs: `AGENTS.md` (*Health and location data* line), `mobile/README.md`, `wiki/relay-phone-sync.md`, `wiki/relay-webhook-changes.md`; website `site/src/content/docs/app/settings.md`, `health.md`, `location.md`, `calendar.md`, `photos.md`, `on-a-computer.md`, `privacy.md`, `health-privacy.md`, `connections/your-database.md`, `start/connect-a-phone.md`, and any other page that names the switch.

## Decision log

- **2026-11-16** — Asked, by Matthew's request from the WongOS chat: remove the mixed mode, so a signed-in phone never sends to a webhook itself → chose one path each: signed in, everything through Relay Everything; no account, everything straight to the phone's own webhook.
- **2026-11-16** — Asked what happens on a phone with *Only to my own webhook* on today → chose move them to the server: health, places, calendar and photos, with what waits, go to Relay Everything, and the app says so once.
- **2026-11-16** — Assumed: the one-time message is a dialog at the next app open, with *OK* and *Open Webhooks*, because a line on a page the person may never open is no notice.
- **2026-11-16** — Assumed: the phone does not add its own webhook to the person's page at sign-in or at the move, because a phone key adds only data and can't change account settings (the relay-webhooks spec refuses a device key); the words tell the person to add it.
- **2026-11-16** — Assumed: the phone keeps the webhook's address and secret after the move and after sign-in, because the no-account mode uses them again after *Sign out*.
- **2026-11-16** — Assumed: signing in from the webhook Account page needs no extra question, because the *Sign in* screen now says, before the button, that everything goes to Relay Everything.
- **2026-11-16** — Assumed: no server change, because the server already takes every kind and sends each to the webhooks ticked for it, with past data on request.
- **2026-11-16** — Assumed: recovering the 25 notes is Matthew's step on his page after the ship, not a build task, because only the signed-in owner can add a webhook.
- **2026-11-16** — Assumed: real pictures come from a screen test on a throwaway copy at c0fb2f7, and the one-time message's picture is drawn from its planned words.
- **2026-11-16** — Asked, by the daily line-up note about `recordings-as-attachments` → chose to name it: both paths, Relay Everything → webhook and no-account phone → webhook, carry recordings as files with their transcripts, and whichever plan lands second follows the other. This plan changes no message, so a check task covers it.
- **2026-11-16** — Assumed, at build: the notes-first split in `flush` stays, renamed `notes:` with the routes as `dataRoutes`, because it carries the shipped *notes first* promise (relay-note-sync: a failed health upload never stops new notes); only its second destination goes.
- **2026-11-16** — Assumed, at build: a move to a new place still drops the calendar's waiting rows with its sent list, as before, because the next read sends the whole window to the new place; health and points rows move in order.
- **2026-11-16** — Assumed, at build: `Settings.hadPrivateWebhook` still reads the old `privateTo` key, so the 5.1 search finds that one line, because the one-time move must read what older builds saved.
- **2026-11-16** — Assumed, at build: task 5.2 needs no new note, because the `recordings-as-attachments` plan already names this plan's one path per webhook (its proposal *Overlap* and design *One path per webhook*), and this change leaves the webhook message code as it is.
- **2026-11-16** — Asked, by the daily line-up note about `recently-deleted` → chose to name it: *note deleted* and the new *note recovered* go on both paths, Relay Everything → webhook and no-account phone → webhook, and whichever plan lands second follows the other. This plan changes no message, so check task 5.3 covers it.
- **2026-11-16** — Assumed, at the checks: the narrow-screen test checks only the *Webhooks* title, not *Add or change on your Relay Everything page*, because that link row wraps at phone width today too; and the move test sets the photos start time, as `setPhotos` does, because a phone with *Photos* on always has one. `flutter analyze` is clean and all 895 phone tests pass.
- **2026-11-16** — Second look: no bug in the code; two weak tests, both fixed. The nights move test now starts its row at the webhook, so it fails if the move does nothing, and a new test closes the one-time message by a tap outside it and checks that the message does not come back.
- **2026-11-16** — Assumed, at 5.3: this change lands before `recently-deleted`, so it left a note for that plan in shared memory: *note deleted* and *note recovered* go on both paths. This change touched no webhook message.
- **2026-11-16** — Saved for final acceptance: built, reviewed, and the spec changes are in the main specs. `flutter analyze` is clean and all phone tests pass. The iPhone device check (5.4) runs on this saved commit.
- **2026-11-16** — Check: the iPhone device check on 9945396 (run 43786411426) gave *works*. The fixed tour passed, with `new-note` on its second try. Claude saw all three scenarios work: Settings and *Sign in* show no *Only to my own webhook* and no private-data group; the webhook Account page's *Sign in to Relay Everything* row and the *Sign in* screen say everything then goes through Relay Everything. The doubled webhook address in Claude's picture came from its own flow typing twice.
- **2026-11-16** — Archived for the ship. The spec deltas were already in the main specs at the last save. The walk reuses the iPhone check on 9945396, because the archive changes no app file.
