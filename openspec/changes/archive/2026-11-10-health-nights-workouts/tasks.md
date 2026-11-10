# Tasks

## 1. Server

- [x] 1.1 Add `schema/space-migrations/0014_nights.sql` (`relay_nights` with its `stages` column, and its index; `kind`, `distance`, `calories` on `relay_health`; `relay_outbox` rebuilt with the `night` kind and its triggers; the `AFTER UPDATE OF kind` health trigger, by the design); `space-schema.test.ts` shows the table and columns, `kinds.test.ts` passes with the new CHECK list; add the step to `wiki/relay-space-migrations.md`
- [x] 1.2 Add `app/worker/apps/relay/nights.ts` with `POST nights` (`asDevice`, at most `BATCH`, upsert by device, source and start, change only when a field differs, at most 400 timeline steps), register it in `api.ts`, add `nights` to `REACH.phone`; in `samples.ts`, take `kind`, `distance` and `calories` only on `workout` and fill them on a resend; `nights.test.ts` and `samples` tests: a resend adds and logs nothing, a changed night or timeline logs once, a timeline over 400 steps gets 400, an old workout fills once and logs once, a field on a non-workout gets 400, a chat key gets 403, and `isolation.test.ts` keeps Ana's nights from Ben
- [x] 1.3 Add `health.nights`, with its timeline, to *Health* in `kinds.ts` and `webhooks/format.ts`, the workout fields on `health.samples`, a `###` heading on `connections/your-database.md` and a branch in `site/public/webhooks/receiver.mjs`; `format.test.ts`, `kinds.test.ts` and the receiver test pass, and a webhook ticked for Health gets the message while an unticked one does not
- [x] 1.4 In `queries.ts`, add `nightPage` and `workoutPage` (newest first, paged, overlap rules by the design) and make `daySummary` add `nights` and `workouts.items`; add made-up nights and workouts to `app/tests/relay-space-rows.sql`; `queries.test.ts` covers paging, two overlapping sources, a duplicate workout, and an old day read as before

## 2. AI connector and API

- [x] 2.1 Add the read-only *nights* and *workouts* tools and `GET /v1/nights` and `GET /v1/workouts` in `relay-mcp/answers.ts`, `inputs.ts`, `openapi.ts`, `tools.ts` and `api.ts`, the *nights* input `stages` (default false) that adds each timeline, and the *day_summary* fields, with times through `local()`; list them under *Health* in `kinds.ts`; `tools.test.ts` and `api.test.ts` check each answer against its schema, that every tool stays read-only, and that a phone key can't read them; run `npm run relay:api-doc`
- [x] 2.2 Update `wiki/stack/relay-ai-connector.md` and `site/src/content/docs/connections/connect-your-ai.md`

## 3. Phone: the rules

- [x] 3.1 Add `mobile/lib/sync/nights.dart` (`SleepReading`, `Night`, `nightsOf`, the stage map and constants, by the design), pure; `nights_test.dart` with made-up readings: a watch night with stages, an awake gap under 2 hours stays one night, over 2 hours makes two, a stage inside `in_bed` never counts twice, an Android session with and without stages, an `in_bed`-only night with 0 asleep, two sources make two nights, and a night at the read's edge is left out, the timeline's order with overlapping readings cut and same-stage steps joined, and a timeline cut at 400 keeping its minutes

## 4. Phone: reading and sending

- [x] 4.1 In `health.dart`: add `nightStages` and, on Android, distance and calories to `allow()` and `askedTypes`; give a `workout` sample `kind`, `distance` and `calories`; read sleep, stages and workouts back 36 hours, make nights, and keep `health.sent` (48 hours, by hash) in the queue's transaction; add the `health.detail` redo and set it in `startHealth`; turning health or sending off empties `health.sent` and `health.detail`; `health_test.dart` covers each with a fake `HealthSource`: a late night sent whole, an unchanged night not queued again, a changed night queued, the redo's weeks and its end, a new phone's start, and other types still read from 2 hours
- [x] 4.2 Add the `nights` outbox route to `privateRoutes` and `queueNights` in `store.dart`, `POST nights` in `api.dart`, `health.nights` and the workout fields in `webhook.dart` (whose test writes the fixture the server's `format.test.ts` reads), and `nights` to Health's *Sent* mark in `outbox.dart`; add `READ_DISTANCE` and `READ_TOTAL_CALORIES_BURNED` to `AndroidManifest.xml`; store, outbox and webhook tests cover the route in both destinations
- [x] 4.3 Update `wiki/relay-phone-sync.md` (the 36-hour read, nights, the sent list, the redo)

## 5. Website

- [x] 5.1 Update `site/src/content/docs/app/health.md` (nights and stages, workout kind, distance and calories, the 36-hour read, the redo, Android's question and its total calories) and `privacy.md` (sleep stages and workout details in the Health row); `node scripts/product-name.test.mjs` passes

## 6. Checks

- [x] 6.1 Run the app tests, `flutter test` and `flutter analyze` in `mobile/`, `node scripts/product-name.test.mjs` and `node scripts/public-check.mjs`
- [x] 6.2 `/save`, then on staging: send a made-up night and a full workout with a phone key, resend both, and see that the AI's *nights* (with and without `stages`), *workouts* and *day_summary* give them once, an old workout gains its kind, and a webhook ticked for Health gets `health.nights`; turn the key off. A real iPhone with a watch is needed to see a real night: the simulator has no health data
