# Tasks

## 1. Server

- [x] 1.1 Add `schema/space-migrations/0013_stays.sql` (`relay_stays` and its index, `relay_outbox` rebuilt with the `stay` kind and its trigger, by the design); `space-schema.test.ts` shows the table, `kinds.test.ts` passes with the new CHECK list; add the step to `wiki/relay-space-migrations.md`
- [x] 1.2 Add `app/worker/apps/relay/stays.ts` with `POST stays` (`asDevice`, at most `BATCH`, upsert by device, kind and start, change only when a field differs), register it in `api.ts`, add `stays` to `REACH.phone`; `stays.test.ts`: a resend adds and logs nothing, a changed end logs once, a bad row gets 400, a chat key gets 403, and `isolation.test.ts` keeps Ana's stays from Ben
- [x] 1.3 Add `location.stays` to *Location history* in `kinds.ts` and `webhooks/format.ts`, a `###` heading on `connections/your-database.md` and a branch in `site/public/webhooks/receiver.mjs`; run `npm run relay:api-doc`; `format.test.ts`, `kinds.test.ts` and the receiver test pass, and a webhook ticked for Location gets the message while an unticked one does not
- [x] 1.4 In `queries.ts`, make `placeVisits` give `{ visits, trips, next }` from `relay_stays` (the longer of two devices' overlapping stays), with the old street runs for points no stay or trip covers, reading on past two or three phones' overlaps, and make `daySummary` give `places` per stay plus `trips`; `queries.test.ts` covers paging, an ongoing stay, two devices, and an old day read as before

## 2. AI connector and the page

- [x] 2.1 In `relay-mcp/answers.ts`, `openapi.ts` and `inputs.ts`, give *places*, *day_summary* and *fetch* the stays and trips by the design, keeping every field they had, with times through `local()`; `tools.test.ts` and `api.test.ts` check each answer against its schema and that every tool stays read-only
- [x] 2.2 Update `app/src/apps/relay/read.ts`'s `Summary` for `places` and `trips`; `App.tsx`'s *Places today* keeps its look; `App.test.tsx` shows a café stay by its name and times
- [x] 2.3 Update `wiki/stack/relay-ai-connector.md` and `site/src/content/docs/connections/connect-your-ai.md`

## 3. Phone: the rules

- [x] 3.1 Add `mobile/lib/sync/stays.dart` (`TimelineState`, `step`, the constants, trip km and mode, by the design), pure; `stays_test.dart` with made-up points and streets: a drive is one trip, a night with no points is one stay, a 30-minute silence makes a one-point stay, two stays 10 minutes apart merge, a 250 m+ fix joins no stay, a slow walk never drags a stay, motion beats speed, each speed band at its edges, an empty 3-hour trip is `unknown`, an ongoing stay opens at 5 minutes, and a sure motion change ends a stay

## 4. Phone: motion, names and visits

- [x] 4.1 iPhone, in `RelayBackground.swift`: a departed `CLVisit` adds its arrival and departure points; the `relay/background` channel answers `venue` (`MKLocalPointsOfInterestRequest`, 50 m) and `motion` (`CMMotionActivityManager.queryActivityStarting`); add `NSMotionUsageDescription` to `Info.plist`; the iOS build in CI passes (not run here: CI builds it)
- [x] 4.2 Android: add `ActivityReceiver.kt` (Transition API, `PendingIntent`, appends to `relay-motion.jsonl`) and a `relay/motion` channel to register, unregister and drain; add `ACTIVITY_RECOGNITION` and the receiver to `AndroidManifest.xml`; the Android build in CI passes (not run here: CI builds it)
- [x] 4.3 In Dart, add a `Motion` interface with the iPhone and Android versions and a fake; ask for motion after the location permission when *Location history* turns on; add the stay name steps (calendar via `sync/calendar.dart` events at a time and `locationFromAddress`, venue on iPhone with a good fix, street, coordinates), at most 3 stays a round; tests with fakes cover each step's order, a link location skipped, an online meeting at home not renaming it, a failed lookup falling through, and sending off asking nothing

## 5. Phone: store, rounds and sending

- [x] 5.1 Raise the store's schema version with `track`, `motions` and the `timeline` state key, plus the `stays` outbox route; store tests cover the upgrade from the version before, and that turning off *Location history* or sending clears them
- [x] 5.2 Run the timeline step in `backgroundRound` and the controller's drain after the points, by the design's order; send `stays` through `RelayApi` (`POST stays`) and, in own-webhook mode, as `location.stays` from `webhook.dart`, whose test writes the fixture the server's `format.test.ts` reads; sync and controller tests cover a stay that opens in one round and closes in the next, and a cut round that keeps points and segments
- [x] 5.3 Add `locationSend` to `Settings` (old settings read `all`), `Relay.setLocationSend` and the controller, and gate the round by the design (*Only points* skips the timeline and the motion ask; *Only stays and trips* never queues points and drops waiting ones when picked); add *What to send* to the Location page by the design's UX; settings, controller, sync and widget tests cover each choice, the drop, and that no `POST locations` goes with *Only stays and trips*
- [x] 5.4 Update `wiki/relay-phone-sync.md` (the timeline step, the open segment kept, motion, the visit's two points)

## 6. Website

- [x] 6.1 Update `site/src/content/docs/app/location.md` (stays, trips and modes, the motion question, how a stay gets its name, *What to send*, from the update on) and `privacy.md` (the phone works out stays; lookups get one stay's coordinates, only with sending on; motion stays on the phone); `node scripts/product-name.test.mjs` passes

## 7. Checks

- [x] 7.1 Run the app tests, `flutter test` and `flutter analyze` in `mobile/`, `node scripts/product-name.test.mjs` and `node scripts/public-check.mjs`
- [ ] 7.2 `/save`, then on staging: send a made-up day of stays and trips with a phone key, and see the page's *Places today* list show the stays, the AI's *places* and *day_summary* give the stays and trips, and a webhook ticked for Location get `location.stays`; turn the key off
