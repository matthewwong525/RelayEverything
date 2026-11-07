# Design

## Context

See proposal.md, Why. Two phone data paths join one change because they share the phone's settings, store, background round and the server's space schema.

- **Health today.** `mobile/lib/sync/health.dart` maps four `HealthDataType`s to server names, reads from `health.since` (first read 7 days, 2-hour overlap) and queues 500-sample `health` uploads. iOS wakes come from `HKObserverQuery`s in `ios/Runner/RelayBackground.swift:134`. On the server the four names are fixed in 8 places, among them a `CHECK` on `relay_health.type` (`schema/space-migrations/0001_relay.sql:40`), `samples.ts:11`, `queries.ts:5`, `webhooks/format.ts:27,55` and `relay-mcp/inputs.ts:49`.
- **Background round.** `backgroundRound` in `mobile/lib/sync/background.dart` drains iOS points, reads health, queues points and flushes, for the hourly Workmanager task and each iPhone wake. An iPhone wake has about 25 s (`BackgroundWake`).
- **Webhooks.** `relay_outbox.kind` has `CHECK IN ('note.created','note.updated','health','location')`; webhook kinds are `notes`, `health`, `locations` (`webhooks/send.ts:12`, `routes.ts:17`, `log.ts:4` `TAKES`).
- **Connector and API.** `TOOLS` (`relay-mcp/inputs.ts`), `READS` (`answers.ts`), `ROUTES` (`relay-mcp/api.ts`) and `ANSWERS` (`openapi.ts`) are tied by `satisfies`; `npm run relay:api-doc` writes the site's API and webhook files.
- **Overlaps.** share-to-relay-everything (busy) edits `mobile/lib/data/store.dart`, `sync/background.dart`, `data/attachments.dart`, `AndroidManifest.xml`, `Info.plist`-adjacent files and `site/sidebar.mjs`. relay-photos (PR #30) adds `0003_photos`, `photos.ts` and webhook and connector entries. Main already has `0003_api_devices` and `0004_attachments`, so this change takes `0005_phone_data`; whichever publishes second renumbers and rebases.

## Goals / Non-Goals

**Goals:**
- Calendar events, eight more health types and 90 days of health history reach the space while sending is on, and reach the connector, API, day summary and webhooks.

**Non-Goals:**
- No meeting or long-recording mode: voice notes stay as they are, and the voice-note fix stays in its own plan (PR #21).
- No calendar writes, reminders, contacts, health records, mood or medicines.

## Decisions

### Calendar

1. **A calendar plugin, not native code.** Use a maintained Flutter calendar plugin that lists calendars and reads event instances with attendees on iOS (EventKit) and Android (`CalendarContract.Instances`): `device_calendar`, or its maintained fork if `device_calendar` does not build with the app's Flutter. `/apply` checks pub.dev and records the pick in this design. Picked: `device_calendar_plus` 0.12.0, the maintained fork (October 2026; `device_calendar` last shipped in 2024); its Android full access needs `WRITE_CALENDAR` declared beside `READ_CALENDAR`, one calendar prompt, and the app still never writes. Alternative: a method channel per platform: full control, but Kotlin and Swift to keep, and the app has no Kotlin today.
2. **`CalendarSource` interface.** `lib/sync/calendar.dart` holds `abstract class CalendarSource { Future<bool> allow(); Future<List<PhoneCalendar>> calendars(); Future<List<PhoneEvent>> events(DateTime from, DateTime to, Set<String> calendarIds); }`, the plugin's `PhoneCalendarSource`, and a test fake, the same shape as `HealthSource`.
3. **Diff sync by fingerprint.** Each round reads `[now − 90 d, now + 90 d]` from the calendars not in `Settings.calendarsOff`. An event's key is `<calendarId>:<eventId>:<startMs>`, so each occurrence of a repeating event is its own row. A new store table `calendar_sent (key TEXT PRIMARY KEY, hash TEXT NOT NULL)` keeps the SHA-256 of each sent event's fields. The round queues events whose hash is new or changed and the keys in `calendar_sent` that are gone from the window's read, inside the window only, as `calendar` uploads of up to 200 events: `{events: [...], removed: [...]}`. It writes `calendar_sent` in the same transaction as the enqueue, so a crash never marks an event sent that has no upload. The first round sends the whole window by the same code. A key that falls out of the window's past edge is dropped from `calendar_sent` with no removal: the event happened. Alternative: send the whole window each hour: a few hundred events, over the 256 KB body cap, and every webhook gets every event each hour.
4. **Event shape.** `{key, calendar, title, start, end, allDay, location?, notes?, url?, people: [{name?, email?, organizer?}]}`. `notes` is capped at 4,000 characters, `title` and `location` at 500, people at 100. Calendar name is sent; calendar id is not.
5. **Settings.** `Settings` gets `calendar` (forced off with sending, like `health`) and `calendarsOff: Set<String>`. Turning `calendar` on asks the phone's permission (iOS 17 full access). Turning a calendar off removes its keys at the next round, by decision 3. Turning `calendar` off or sending off deletes waiting `calendar` uploads and empties `calendar_sent`, so turning it on again sends the window again.
6. **When it runs.** In `backgroundRound` after health, and at app open, through the same `syncCalendar(store, source, settings, now)`. iOS wakes for health and places carry it; there is no calendar wake. Settings shows *Last sent* from a `sent.calendar` state key, set by `flush`'s `_sentKeys`.

### Health

7. **Ten new server names.** `weight` (kg), `resting_heart_rate` (bpm), `hrv_sdnn` (ms, iPhone), `hrv_rmssd` (ms, Android), `blood_oxygen` (%, 0 to 100; a 0-to-1 reading is multiplied by 100), `blood_pressure_systolic` and `blood_pressure_diastolic` (mmHg), `cycle_flow` (0 none, 1 light, 2 medium, 3 heavy; unspecified is 1), `mindful` (min, iPhone; duration like sleep), `water` (ml from the package's litres). Android lacks `MINDFULNESS` in `health` 13.3.2. Alternative: one `hrv` type: SDNN and RMSSD differ by method and can't be averaged together.
8. **One list per side.** `kinds` in `health.dart` grows; `_units` follows. On the server one exported `HEALTH_TYPES` const in `queries.ts` feeds `samples.ts`, `webhooks/format.ts` and `relay-mcp/inputs.ts`, so a later type is one edit.
9. **Permissions.** `PhoneHealth.allow()` asks for every type; HealthKit and Health Connect show a switch per type, and a refused type reads as empty, not an error. Android adds `READ_WEIGHT`, `READ_RESTING_HEART_RATE`, `READ_HEART_RATE_VARIABILITY`, `READ_OXYGEN_SATURATION`, `READ_BLOOD_PRESSURE`, `READ_MENSTRUATION`, `READ_HYDRATION`; `READ_HEALTH_DATA_HISTORY` is already there, so 90 days read. iOS `NSHealthShareUsageDescription` lists the new types, and `RelayBackground.swift` observes the new types with hourly background delivery. A phone that already allowed health is asked again once at the next app open for the new types (`health.types` state key holds the asked list).
10. **Backfill by week, newest first.** A state key `health.backfill` holds the oldest day read so far. While it is newer than 90 days ago, each round reads one more 7-day window before it, queues it in 500-sample batches, and moves the mark. The normal `health.since` read runs first, so new readings never wait behind history. A phone updating with `health.since` set and no `health.backfill` starts its backfill at `health.since`'s first read, which covers the new types. Alternative: one 90-day read: an Apple Watch writes thousands of heart readings a day, past the 25-second wake and the phone's memory.
11. **Server stops checking type names in SQL.** `0005_phone_data.sql` rebuilds `relay_health` with no `type` `CHECK`, by the `0003_api_devices.sql` copy pattern, and recreates its `relay_outbox_health` trigger and `start_at` index. Code checks the names (decision 8).
12. **Summary.** `HEALTH` in `queries.ts` gets: weight latest; resting heart rate and HRV average; blood oxygen min and average; blood pressure each reading (time, upper, lower), up to 20 a day; cycle flow the day's highest; mindful and water largest source summed, like sleep. `daySummary`, `summary.ts`, the `day_summary` tool and `getDay` add these, leaving a type out when the day has none.

### Server

13. **Migration `0005_phone_data.sql`.** Rebuild `relay_health` (decision 11); rebuild `relay_outbox` with `'calendar'` in its `kind` `CHECK` and recreate all outbox triggers; create `relay_calendar_events (id INTEGER PRIMARY KEY, device_id TEXT NOT NULL REFERENCES relay_devices(id), event_key TEXT NOT NULL, calendar TEXT, title TEXT, start_at INTEGER NOT NULL, end_at INTEGER NOT NULL CHECK (end_at >= start_at), all_day INTEGER NOT NULL DEFAULT 0, location TEXT, notes TEXT, url TEXT, people TEXT NOT NULL DEFAULT '[]', removed_at INTEGER, updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL, UNIQUE (device_id, event_key))`, an index on `start_at`, and outbox triggers on insert and on update.
14. **`POST calendar`.** `app/worker/apps/relay/calendar.ts` defines the route with the `batch` builder in `samples.ts`; `caller.ts` lets phone keys reach it. Upsert by `(device_id, event_key)` with `ON CONFLICT DO UPDATE ... WHERE` any field differs or `removed_at` is set, so a resend changes nothing and wakes no webhook; `removed` keys set `removed_at`. Answer `{received, changed, removed}`. Reads skip removed rows.
15. **Webhooks.** Kind `calendar` in `send.ts`, `routes.ts` (max 4), `log.ts` `TAKES`; `format.ts` message `calendar.events` with each event and `status: "changed" | "removed"`; `Webhooks.tsx` adds the *Calendar* tick; *Send past data* includes it.
16. **Connector and API.** Tool `calendar {from, to, q?, limit, cursor?, timezone}` (read-only, newest first when `q` is set, else by start), `READS.calendar` from a `listEvents` query in `queries.ts`; route `GET /v1/calendar` (`listEvents`) and its `ANSWERS` entry; `day_summary`/`getDay` add the day's events (title, start, end, people names); `health`'s type enum takes `HEALTH_TYPES`. `fetch` stays notes and chats.
17. **Page.** `app/src/apps/relay/App.tsx` shows the day's events and the new health values beside the steps and sleep tiles; `read.ts` types follow; `Devices.tsx` labels a phone key *Notes, health, places and calendar*.

## UX

### Use-case brief
A person who connects their phone once and then forgets it. They turn the calendar on in Settings, allow the phone's calendar, and may turn off a calendar that adds noise, such as holidays. Edge cases: the person refuses the phone's permission; a calendar is removed from the phone; sending is off.

### Flow
Settings → *Calendar* switch → the phone's permission → the calendar list, all on → turn one off if wanted → *Last sent* fills in after the next round.

### Hierarchy
- **Settings:** the *Calendar* switch sits under *Health*, with *Last sent*; the calendar list shows only while it is on, each with its own switch.

### Review
review.html; What Changes sketches the Settings calendar list.

### Components
Existing: switches and *Last sent* rows in `screens/settings.dart`. New: none.

## Risks / Trade-offs

- [The calendar plugin does not run in the iPhone's headless background engine] → The calendar then syncs at app open and in Android's hourly round only; the device check and the TestFlight check show it. Recorded as a follow-up, not a block.
- [A 90-day backfill of heart rate is many uploads] → 500-sample batches, oldest-first flush order kept; the server keeps each once.
- [Webhook receivers that check the health `type` enum] → The webhook format stays v1 and its schema lists the new types; additive.
- [Cycle data is private] → It goes only to the person's own space and the webhooks they tick for health, like every type; the phone's permission screen lets them leave it off.
- [Two open plans add migrations] → The second to publish renumbers (`0003_photos` must move past `0005`, or this file moves).

## Migration Plan

- Space migration `0005_phone_data` runs once per space at its next request; it keeps every health row and outbox row.
- Phone store schema 5 → 6 adds the `calendar_sent` table only.
- An updated phone with health on asks once for the new types and runs the 90-day backfill once.
- Rollback: the old app ignores the new server kinds; the server keeps rows it got.
