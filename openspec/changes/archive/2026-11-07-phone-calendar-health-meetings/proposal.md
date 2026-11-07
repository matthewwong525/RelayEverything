# Proposal: Your phone's calendar and more health

**Status:** ready-to-ship
**Branch:** innocent-stingray
**Open questions:** none

## Why

When you connect your phone and open Claude, it should know your day at once: who you meet, and how you slept and feel. Today Relay Everything sends only steps, heart rate, sleep and workouts, for the last 7 days. It has no calendar. This change adds your phone's calendar, and eight more health types with 90 days of history.

## What Changes

**What you get**

- **Your phone's calendar goes to your space.** Relay Everything reads every calendar on the phone: Google, iCloud, Outlook, work and subscribed ones, with no Google sign-in. It reads, and never changes an event. It sends the last 90 days and the next 90 days the first time, then each change and each removed event. It sends only while *Send to Relay Everything* is on. You can turn single calendars off, such as a holiday calendar.
  ```screen
  <div class="card col gap phone">
    <h3>Settings</h3>
    <div class="row gap"><span class="grow">Calendar</span><span class="tag">On</span></div>
    <span class="muted">Sends your events from the phone's calendars. Last sent 10:42 AM.</span>
    <div class="sep"></div>
    <div class="row gap"><span class="grow">Work (Google)</span><span class="tag">On</span></div>
    <div class="row gap"><span class="grow">Home (iCloud)</span><span class="tag">On</span></div>
    <div class="row gap"><span class="grow">US Holidays</span><span class="tag-outline">Off</span></div>
  </div>
  ```
  This sketch stands in for a picture: the phone app does not run in the plan's preview.
- **Your AI, your scripts and your webhooks get the calendar.** A new *calendar* tool in the AI connector and the web API reads events by time or words, with title, time, place, notes and people. The day summary lists the day's events. A webhook you tick for *Calendar* gets each new, changed and removed event.
  | You ask Claude | It reads |
  | --- | --- |
  | What is on my day? | Today's events, with people |
  | When did I last meet Sam? | Events with Sam, newest first |
  | How did I sleep before the board meeting? | The event, then that night's sleep |
- **Eight more health types.** Weight, resting heart rate, heart rate variability, blood oxygen, blood pressure, cycle, mindful minutes and water. The phone asks for each one in its own health permission screen, so you can leave any type off. Mindful minutes come from iPhone only: Android's health store does not give them to the app yet.
  | Type | Sent as | Day summary |
  | --- | --- | --- |
  | Weight | kg | latest |
  | Resting heart rate | bpm | average |
  | Heart rate variability | ms | average |
  | Blood oxygen | % | lowest and average |
  | Blood pressure | mmHg, upper and lower | each reading |
  | Cycle | flow, none to heavy | flow that day |
  | Mindful minutes | minutes | total |
  | Water | ml | total |
- **90 days of health history on day one.** When you turn health on, the phone sends the last 90 days, newest week first, a little each round, so Claude has history at once. A phone that already sends health gets the same 90 days once after the update, for every type.
  ```mermaid
  flowchart LR
    A[Health on] --> B[Newest week]
    B --> C[Older weeks]
    C --> D[Each hour]
  ```
- **The website says all of it.** The pages on health, settings, the AI connector, the API and webhooks list the new data, and a new page explains the calendar.

**What of yours stays**

- **Sending off still means nothing leaves the phone.** With sending off, the app reads no calendar and no health.
- **Your notes, health and places stay as they are.** The server keeps every reading it has.

**What is left out, and why**

- **No meeting recordings.** A recording is a voice note, the same as today. The voice-note fix stays in its own plan.
- **Not in this change:** mood, medicines, reminders, health records, contacts, screen time, the call log, notifications, photos (its own plan), a Google connection, a *my day* tool and suggested questions.

**What you do yourself**

- **On your iPhone, from TestFlight:** turn on the calendar and health, and see today's events and 90 days of health in Claude.

## What the build needs

- **The App Store Connect key with Admin access**: Ready. It is in the repository's secrets and in this computer's private settings file.

## Decision log

- **2026-11-07** — Assumed: this plan covers calendar and more health types (items 1 and 3 of the ranked list), because photos (item 2) has its own plan in PR #30, and longer recordings (item 4) were dropped (below).
- **2026-11-07** — Asked where a meeting's recording goes → chose it stays on the phone; only the words go.
- **2026-11-07** — Asked how the waiting voice-note fix (PR #21) comes in → chose to put it in this change; PR #21 closes.
- **2026-11-07** — Assumed: calendar goes by the phone's own calendars, not a Google connection, because the research chat settled it and the Gmail and Calendar connector is parked.
- **2026-11-07** — Assumed: every calendar is on, with a switch per calendar in Settings, because a holiday or shared calendar adds noise and a private one may not belong in the space.
- **2026-11-07** — Assumed: the calendar window is 90 days back and 90 days ahead, and each round sends only new, changed and removed events, because the past rarely changes and a full copy each hour wastes signal.
- **2026-11-07** — Assumed: the health backfill is 90 days, newest week first, a week each round, because an iPhone's background round lasts about 25 seconds and a watch writes thousands of heart readings a day.
- **2026-11-07** — Assumed: heart rate variability keeps the phone's own measure (iPhone SDNN, Android RMSSD) as two types, because the two numbers can't be compared.
- **2026-11-07** — Assumed: the server stops listing health types in its table rules and checks them in code, because each new type would otherwise need a table rebuild.
- **2026-11-07** — Asked in a note on the plan for no meeting mode → chose a long recording is a voice note like any other: no meeting type, no calendar event link, no people, no typed-notes box, no *Start a meeting* action.
- **2026-11-07** — Asked (Matthew, passed on by another chat) to drop meeting recordings from this plan → chose no continuous-recording mode at all; this plan covers only the phone's calendar and more health types with the 90-day backfill.
- **2026-11-07** — Assumed: the voice-note fix goes back to its own plan (PR #21), because it came in only because meeting words needed it.
- **2026-11-07** — Assumed: POST calendar is its own action, not the health and location batch builder, because its body holds two lists (events and removed keys) and its answer counts both.
- **2026-11-07** — Assumed: the new-types health batch test sits in `app/worker/apps/relay/api.test.ts` beside the other batch tests, because `device.test.ts` tests which key reaches which route; it gets the calendar route there.
- **2026-11-07** — Assumed: a webhook's `calendar.events` message holds up to 500 events, like the other kinds' groups, because the send log groups up to 500 rows of one kind.
- **2026-11-07** — Assumed: a calendar's name is cut to 200 characters on the phone and refused past 200 on the server; the day summary lists up to 50 events.
- **2026-11-07** — Assumed: the calendar sample rows go in `app/tests/relay-space-rows.sql`, because a person's space has no rows in `schema/seed.sql`.
- **2026-11-07** — Assumed: the calendar plugin is `device_calendar_plus` 0.12.0, and Android also declares `WRITE_CALENDAR`, because the plugin asks for full access; the app never writes.
- **2026-11-07** — Assumed: a cancelled event is sent as a removal, hidden calendars are not listed, and a refused calendar permission removes nothing already sent.
- **2026-11-07** — Assumed: spotting and unspecified cycle flow count as 1 (light), and a blood oxygen value of 1 or less is a fraction, so the phone multiplies it by 100.
- **2026-11-07** — Assumed: a calendar read that fails does not fail the background round; the health and location parts still send.
- **2026-11-07** — Assumed: the phone asks once, at app open, for the new health types (`health.types` key), and with no `health.since` mark it reads the newest week first.
- **2026-11-07** — Assumed: the phone's calendar and health rules go on a new wiki page, `wiki/relay-phone-sync.md`, because no page owned them.
- **2026-11-07** — Assumed: the website publish after the merge (`node scripts/publish-relay-site.mjs`, reported by its `result=` line) is a step after publishing, not a task, because a check only possible after publishing can't be ticked before the merge.
- **2026-11-07** — Assumed: Matthew's own check on his iPhone from TestFlight (turn on the calendar and health; Claude's connector shows today's events and 90 days of weight or heart rate) comes after publishing, not as a task, because TestFlight gets the build only after the merge.
- **2026-11-07** — Built: server, web page, phone and docs, with the review's two backfill fixes; specs reconciled; saved for the pull request's checks inside /ship.
- **2026-11-07** — Assumed: task 6.3 checks only what the simulator can show (the calendar switch, and no permission ask with sending off), because the simulator can't sign in to a server, so sending and the calendar list stay off there; the device check said works, and `screens_test.dart` and Matthew's TestFlight check cover the list.
- **2026-11-07** — Archive checkpoint inside /ship: the checks, the iPhone simulator check (works) and the staging site passed. Main's iPhone build had failed on Apple's certificate limit; asked whether to revoke the two *Created via API* certificates → chose revoke both, and main's build passed. Main then took space migration `0005_no_pebble`, so this change's migration became `0006_phone_data` and no longer makes the dropped `relay_outbox_note_updated` trigger again.

## Capabilities

### New Capabilities

- `relay-calendar`: the phone reads its calendars while sending is on, sends new, changed and removed events, and the space keeps and serves them.

### Modified Capabilities

- `relay-sending`: the calendar joins health and location history as data read and kept only while sending is on.
- `relay-sync`: health covers eight more types and a 90-day first read.
- `relay-webhooks`: a webhook can take the calendar kind.
- `relay-ai-connector`: a read-only calendar tool, and the new health types.
- `relay-api`: calendar reads, and the new health types.

## Impact

- Phone app (`mobile/`): new `lib/sync/calendar.dart`; changes to `lib/sync/health.dart`, `lib/sync/background.dart`, `lib/data/settings.dart`, `lib/data/store.dart` (schema 6), `lib/data/outbox.dart`, `lib/controller.dart`, `lib/screens/settings.dart`; `ios/Runner/Info.plist` (calendar, health text), `ios/Runner/RelayBackground.swift` (new health types); `android/app/src/main/AndroidManifest.xml` (calendar, health). New package: a calendar plugin.
- Server (`app/worker/`): `schema/space-migrations/0005_phone_data.sql`; `apps/relay/samples.ts`, `calendar.ts` (new), `caller.ts`, `api.ts`, `queries.ts`, `summary.ts`, `webhooks/*`; `relay-mcp/inputs.ts`, `answers.ts`, `api.ts`, `openapi.ts`.
- Web page (`app/src/apps/relay/`): `Webhooks.tsx`, `App.tsx`, `read.ts`, `Devices.tsx`.
- Website (`site/`): health, settings, connector, API, webhooks and privacy pages, a new calendar page, regenerated API and webhook files.
- Overlaps: share-to-relay-everything (busy workspace, same mobile store and background files) and relay-photos (PR #30, takes migration `0003_photos`). Whichever publishes second renumbers its migration and catches up.
