# Send health, places, calendar and photos only to your own webhook, while your notes still sync

**Status:** in-progress
**Branch:** keep-health-location-off-server
**Open questions:** none

## Why

Today the phone sends everything to one place: Relay Everything, or your own webhook. A person who wants their notes to sync across phones must also send their health, places, calendar and photos through our server. Some people want note sync but do not want their personal data on a server they do not run.

## What Changes

- **A new choice on the Account page: where your private data goes.** Signed in to Relay Everything, the Account page gets a group *Health, places, calendar and photos* with two choices. *Relay Everything* is the default and works as today. *Only my own webhook* sends them straight from this phone to your webhook, and Relay Everything never gets them. Your notes, their files and a note's pinned place still sync through Relay Everything. No real picture: the phone app is Flutter, which the plan's prototype can't run, and the signed-in Account page needs an account the iPhone check doesn't have.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹ Settings</button></div>
    <h3>Account</h3>
    <div class="card col gap"><b>you@example.com</b><span class="muted">app.relayeverything.com</span></div>
    <span class="muted">Connections</span>
    <div class="card col gap"><div class="row gap"><span class="grow">AI apps</span><span class="muted">Claude · 1 ›</span></div><span class="sep"/><div class="row gap"><span class="grow">Webhooks</span><span class="muted">My database · 1 ›</span></div></div>
    <span class="muted">Health, places, calendar and photos</span>
    <div class="card col gap"><div class="row gap"><div class="col grow"><span>Relay Everything</span><span class="muted">Your AI and your page can see them.</span></div><span class="tag">✓</span></div><span class="sep"/><div class="row gap"><div class="col grow"><span>Only my own webhook</span><span class="muted">Straight from this phone. Relay Everything never gets them.</span></div></div></div>
    <div class="card col gap"><div class="row gap"><span class="grow">Open your Relay Everything page</span><span class="muted">↗</span></div><span class="sep"/><div class="row gap"><span class="grow">Server</span><span class="muted">app.relayeverything.com ✎</span></div></div>
    <div class="card col gap"><span class="danger">Sign out</span></div>
  </div>
  ```
- **Picking *Only my own webhook* sets up the webhook on the phone.** With no webhook kept, the phone opens the same webhook screen as *Send to my own webhook instead*: you type its address, copy its new secret, and *Send a test*. A webhook you added on your Relay Everything page does not count, because the server never gives its secret to a phone. Once set, the group shows the webhook's address, *Send a test*, and the last failure, if any. A line under the group says that what already went stays on your Relay Everything page.
  ```screen
  <div class="card col gap phone">
    <span class="muted">Health, places, calendar and photos</span>
    <div class="card col gap"><div class="row gap"><div class="col grow"><span>Relay Everything</span><span class="muted">Your AI and your page can see them.</span></div></div><span class="sep"/><div class="row gap"><div class="col grow"><span>Only my own webhook</span><span class="muted">Straight from this phone. Relay Everything never gets them.</span></div><span class="tag">✓</span></div><span class="sep"/><div class="row gap"><div class="col grow"><span>Webhook</span><span class="muted">db.example.com</span></div><button class="btn-ghost">Send a test</button></div></div>
    <span class="muted">What already went to Relay Everything stays on your page. Your AI apps and your page show none of this from now on.</span>
  </div>
  ```
- **Two ways out of the phone at once.** Notes go to Relay Everything and private data goes to the webhook, each in its own order. A webhook that is down holds back only the private data; your notes still sync, and the other way round. Nothing private ever falls back to Relay Everything: if the webhook is gone, such as after a phone restore, private data waits on the phone and the Account page asks you to set the webhook again.
  ```mermaid
  flowchart TD
    P["Phone"] -->|"notes"| R["Relay Everything"]
    P -->|"private data"| W["Your webhook"]
    R -->|"notes"| W
  ```
  ```screen
  <div class="card col gap phone">
    <span class="muted">Health, places, calendar and photos</span>
    <div class="card col gap"><div class="row gap"><div class="col grow"><span>Only my own webhook</span><span class="muted">Straight from this phone. Relay Everything never gets them.</span></div><span class="tag">✓</span></div><span class="sep"/><div class="row gap"><div class="col grow"><span class="danger">Set your webhook again</span><span class="muted">This phone lost its address and secret. Your health, places, calendar and photos wait here until you do.</span></div><span class="muted">›</span></div></div>
  </div>
  ```
- **Switching back sends what waits to the new place.** Picking *Relay Everything* again sends the private data still waiting on the phone there, and the calendar's window goes there in full, as a change of place does today. Signing out stops both, as today, and keeps the webhook's address and secret.
- **The folders and the website say where the data goes.** *Health*, *Location*, *Calendar* and *Photos* say *Sent to your webhook* in place of the last time it reached Relay Everything. The website's Settings, Health, Location, Calendar, Photos and privacy pages explain the choice and what you give up.

Non-goals: no change to the server, its webhooks or the AI connector; no per-kind choice; no delete of data already on the server; *Send to my own webhook instead* (no account) stays as it is.

**What you give up with *Only my own webhook*:** your AI apps' health, places, calendar and photos tools and your Relay Everything page show none of it from then on. No server retries for you: when the phone is off or offline, the data waits for the phone's next round.

## What the build needs

- **Nothing.** The phone already signs and sends to a webhook, and its waiting list already knows which place each item goes to.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-phone-webhook`: a signed-in phone can send health, location points, calendar events and photos straight to its own webhook, while notes go to Relay Everything; failures on one side never hold back the other.
- `relay-sending`: signing in still picks one place for notes; private data may go to a second place, the person's own webhook, never to both.
- `relay-photos`: photos go where private data goes, which may differ from where notes go.
- `relay-home-screen`: the Account page, signed in, shows the private data choice and, when on, the webhook.

## Impact

- `mobile/lib/data/settings.dart`: a new saved field for where private data goes; old settings read as Relay Everything.
- `mobile/lib/data/store.dart`: a second destination for private routes (`health`, `locations`, `calendar`), picked at enqueue; `moveOutbox` moves each group to its own place and drops the calendar's sent list when the private place changes.
- `mobile/lib/data/outbox.dart`: `flush` sends only its client's destination and skips the other's items, so two places flush apart.
- `mobile/lib/data/sender.dart`: a client for private data next to the notes client.
- `mobile/lib/controller.dart`, `mobile/lib/sync/background.dart`: each round flushes both clients and sends photos through the private client; `relay.dart` gains the choice and its setter.
- `mobile/lib/screens/account.dart`: the new group; `connect.dart`'s webhook screen opens from it; `folder.dart` status lines.
- Tests: `mobile/test/` store, outbox, controller, background and screen tests.
- iPhone check: a scenario for the signed-out Account path only; the check has no account, so widget tests cover the signed-in group.
- Docs: `mobile/README.md`, `wiki/relay-phone-sync.md`; website `site/src/content/docs/app/settings.md`, `health.md`, `location.md`, `calendar.md`, `photos.md`, `privacy.md`, `health-privacy.md`; `AGENTS.md` / `CLAUDE.md` *Health and location data* line.

## Decision log

- **2026-11-08** — Asked whether people who want note sync can keep health and places off our server → chose to plan a setting for it, built on PR #72's Account page.
- **2026-11-08** — Asked one switch or one per kind → chose one switch for all private data (the recommendation, accepted with *go plan it*).
- **2026-11-08** — Asked what happens to health and places already on the server → chose keep it; the switch says so plainly.
- **2026-11-08** — Asked which data the switch covers → chose everything but notes: health, location history, calendar and photos.
- **2026-11-08** — Assumed: a note's pinned place stays with the note and syncs through Relay Everything, because it is part of the note; *Pin notes to where I am* already turns it off.
- **2026-11-08** — Assumed: the choice lives on the Account page, not in Settings or the folders, because the Account page owns where data goes since #72.
- **2026-11-08** — Assumed: the phone keeps its own webhook address and secret, the same one *Send to my own webhook instead* uses, because the server never gives a webhook's secret to a phone key.
- **2026-11-08** — Assumed: private data never falls back to Relay Everything when the webhook is missing or down; it waits on the phone, because a silent fallback breaks the promise.
- **2026-11-08** — Assumed: switching back to *Relay Everything* sends what waits there, as today's change of place does, because the person chose it.
- **2026-11-08** — Assumed: no prototype pictures, because the phone app is Flutter and the plan's prototype runs only the web app; widget tests and the iPhone check show the built screens.
- **2026-11-08** — Assumed, from the daily line-up note: plan on top of PR #72; it merged at 22:57 UTC while planning, so the plan starts from main at 85e401f.
- **2026-11-09** — Assumed, at build: the settings tests for `privateTo` went in `controller_test.dart`'s settings group, where every other `Settings` test lives, not `data_test.dart`.
- **2026-11-09** — Assumed, at build: a background round with no webhook for private data still reports done, because no retry can send it before the person sets the webhook again; a receiver that fails makes the round report not done.
- **2026-11-09** — Assumed, at build: Home's folder rows keep *Sent 14:05*; the folder pages say *Sent to your webhook 14:05*, as the plan names them.
- **2026-11-09** — Assumed: a change of the private place clears the last-sent times of health, places and the calendar, because a folder must never say *Sent to your webhook* for data that went to Relay Everything.
- **2026-11-09** — Saved for final acceptance: built, and a second review found four gaps, all fixed: a folder could say *Sent to your webhook* with the time of a send to Relay Everything, and three website pages (your database, privacy, calendar) still said the phone sends to one place only. `flutter analyze` is clean and all 506 phone tests pass. The iPhone device check (5.2) runs on this saved commit.
