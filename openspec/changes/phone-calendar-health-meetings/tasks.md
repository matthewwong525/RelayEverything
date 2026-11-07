## 1. Server: space schema, health types and calendar storage

- [x] 1.1 Write `schema/space-migrations/0005_phone_data.sql` (design 11, 13): rebuild `relay_health` with no `type` `CHECK`, rebuild `relay_outbox` with `'calendar'` in its `kind` `CHECK`, recreate every outbox trigger and index, create `relay_calendar_events` with its index and insert and update triggers; add it to `MIGRATIONS` in `app/worker/spaces-worker.ts`. Verify: `app/worker/apps/relay/space-schema.test.ts` migrates a space that holds health, outbox and note rows and finds them all kept, and a new type stores.
- [x] 1.2 Export `HEALTH_TYPES` from `app/worker/apps/relay/queries.ts` with the ten new names (design 7, 8) and use it in `samples.ts`, `webhooks/format.ts` and `relay-mcp/inputs.ts`. Verify: `device.test.ts` stores a batch of every new type and refuses an unknown one.
- [x] 1.3 Add the new `HEALTH` summaries in `queries.ts` and their fields in `daySummary` and `summary.ts` (design 12). Verify: `queries.test.ts` cases for weight latest, blood pressure readings, cycle flow highest, and water and mindful largest source.
- [x] 1.4 Add `app/worker/apps/relay/calendar.ts` with `POST calendar` (design 14), wire it in `api.ts` and `caller.ts`, and add a `listEvents` query in `queries.ts`. Verify: tests for first store, a resend storing nothing new and waking no outbox row, a changed event, a removed key, and a key from another person's space never read (`isolation.test.ts`).

## 2. Server: webhooks, connector, API and page

- [x] 2.1 Add the `calendar` webhook kind in `webhooks/send.ts`, `routes.ts`, `log.ts` and the `calendar.events` message in `format.ts` (design 15). Verify: `send.test.ts` sends changed and removed events only to a webhook ticked for the calendar; `format.test.ts` checks the schema.
- [x] 2.2 Add the `calendar` tool and `READS.calendar`, the `GET /v1/calendar` route and its `ANSWERS` entry, the day's events in `day_summary` and `getDay`, and the new health types in the `health` tool (design 16). Verify: `relay-mcp/tools.test.ts` lists `calendar` as read-only and bounded by `limit`; `relay-mcp/api.test.ts` checks every answer against `ANSWERS`.
- [x] 2.3 Add the *Calendar* tick to `app/src/apps/relay/Webhooks.tsx`, the day's events and new health values to `App.tsx` and `read.ts`, and the phone key label in `Devices.tsx` (design 15, 17). Verify: `App.test.tsx` and the webhooks test render them from sample data.
- [x] 2.4 Run `npm run relay:api-doc` in `app/` and keep the regenerated `site/public/api/v1.openapi.json`, `site/public/webhooks/v1.schema.json`, `site/src/content/docs/api/reference.md` and `v1-reference.md`. Verify: `api-doc.test.ts` and `openapi.test.ts` pass with no diff after a second run.

## 3. Phone: health

- [x] 3.1 Add the ten types and their units to `mobile/lib/sync/health.dart`, with blood oxygen and water conversions and cycle flow numbers (design 7). Verify: `sync_test.dart` turns a fake point of each type into the server's sample, and skips an unknown type.
- [x] 3.2 Add the 90-day weekly backfill and the one-time ask for new types (design 9, 10). Verify: `sync_test.dart` drives rounds with a fake source until the mark reaches 90 days, checks newest-first order and that `health.since` reads first, and checks an updated phone starts its backfill once.
- [x] 3.3 Add the Android health permissions to `AndroidManifest.xml`, the new types to `NSHealthShareUsageDescription` in `Info.plist`, and the new observed types in `ios/Runner/RelayBackground.swift`. Verify: `flutter build apk --debug` and the iOS CI build pass.
- [x] 3.4 Update `site/src/content/docs/app/health.md` and `site/src/content/docs/privacy.md` with the new types, the per-type permission and the 90 days.

## 4. Phone: calendar

- [x] 4.1 Add the calendar plugin to `mobile/pubspec.yaml` (design 1, record the pick in design.md), `NSCalendarsFullAccessUsageDescription` and `NSCalendarsUsageDescription` to `Info.plist`, and `READ_CALENDAR` to `AndroidManifest.xml`.
- [x] 4.2 Write `mobile/lib/sync/calendar.dart`: `CalendarSource`, `PhoneCalendarSource`, the event shape and `syncCalendar` with the `calendar_sent` diff (design 2 to 4); add the `calendar_sent` table to `mobile/lib/data/store.dart` schema 6. Verify: `sync_test.dart` with a fake source covers the first send, a moved event, a deleted event, a calendar turned off, an event leaving the window's past edge with no removal, and batches of 200.
- [x] 4.3 Add `calendar` and `calendarsOff` to `mobile/lib/data/settings.dart`, the switch, permission ask, calendar list and *Last sent* to `mobile/lib/screens/settings.dart`, the `sent.calendar` key to `outbox.dart`, and the call in `backgroundRound` and at app open (design 5, 6). Verify: `data_test.dart` (settings round-trip, forced off with sending), `offline_test.dart` (sending off reads no calendar and turning it off deletes waiting calendar uploads), `screens_test.dart` (the list shows only while on).
- [x] 4.4 Write `site/src/content/docs/app/calendar.md`, add it to `site/sidebar.mjs` and `scripts/product-name.test.mjs`, and update `site/src/content/docs/app/settings.md`.

## 5. Docs for connections and the wiki

- [x] 5.1 Update `site/src/content/docs/connections/your-database.md`, `connections/connect-your-ai.md` and `api/connect-a-service.md` with the calendar kind, the calendar tool and route, and the new health types.
- [x] 5.2 Update `wiki/relay-spaces.md` and `wiki/stack/relay-ai-connector.md` with the calendar table, kind and tool, and add the calendar diff-sync and health backfill rules (design 3, 10) to the owning mobile wiki page.

## 6. Checks

- [x] 6.1 Run `flutter analyze` and `flutter test` in `mobile/`, `npm test` and the type check in `app/`, `node scripts/product-name.test.mjs` and `node scripts/public-check.mjs`; all pass.
- [ ] 6.2 `/save`; the pull request's checks pass, including the Android and iOS builds.
- [ ] 6.3 Run the device check on the iPhone simulator through `/verify`: Settings shows the calendar switch and the calendar list (no health in the simulator).
- [ ] 6.4 Preview the website with `node scripts/publish-relay-site.mjs --ref HEAD --staging` and check the calendar and health pages.
