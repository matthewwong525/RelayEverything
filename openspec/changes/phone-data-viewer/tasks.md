# Tasks

## 1. Server: a day's totals for a phone

- [ ] 1.1 Add `app/worker/apps/relay/day.ts` (`relay.day`: `daySummary` without `events` and `notes`, `asPersonOrPhone`), register `GET day` in `api.ts`, and add `day` to `PHONE_READS` in `caller.ts`; verify route tests: a phone key and a session get the day from their own space with no `events`, a chat key and an API key are refused, and Ana's phone key never reads Ben's day.
- [ ] 1.2 Keep `space-access.test.ts` and the existing "phone key tries to read health" tests passing for `GET summary` and `GET timeline`; verify `npm test` in `app/` passes.
- [ ] 1.3 Run `npm run relay:api-doc` in `app/`; verify `api-doc.test.ts` passes.
- [ ] 1.4 Add a stay, a trip and a day of health rows for the seed person to `schema/seed.sql` if the seed has none; verify the seed applies with `npx wrangler d1 execute` on local.
- [ ] 1.5 Update the device-key line in `AGENTS.md` (the Relay Everything block) and `wiki/relay-spaces.md#how-a-space-is-opened` to say a phone key reads one day's totals and stays and trips; verify `node scripts/product-name.test.mjs` and the wiki link check pass.

## 2. Phone: the two pages

- [ ] 2.1 Add `Api.day(date, offset)` in `mobile/lib/data/api.dart`; verify an `api_test.dart` case for the query and the parsed answer.
- [ ] 2.2 Add a shared `DayPicker` (*Today*, *Yesterday*, weekday and date; › stops at today) in `mobile/lib/screens/`; verify widget tests for the labels and the stop.
- [ ] 2.3 Add `health_data.dart`: the sync card, each health total the day has, the empty day, and *Can't reach Relay Everything.* with *Try again*; verify widget tests with a fake API for a watch day, an empty day and a failed call.
- [ ] 2.4 Add `places_data.dart`: the sync card with the waiting line, stays and trips in order with *Now* on the ongoing stay, the empty day, and the error; verify widget tests for the morning-out scenario and uploads waiting.
- [ ] 2.5 Add the *See your data* row to `HealthPage` and `LocationPage` in `folder.dart`, shown only when signed in, both places are Relay Everything, and the folder's switch is on; verify widget tests that the row is absent when signed out, with the private place on the webhook, and with the switch off, and that it opens the page.

## 3. Website

- [ ] 3.1 Add a *See your data* section to `site/src/content/docs/app/health.md` and `location.md`, and say in `privacy.md` and the device-key docs that a phone key reads a day's totals and stays and trips; verify `node scripts/product-name.test.mjs` and the site build pass.

## 4. Checks

- [ ] 4.1 Run `flutter analyze` and `flutter test` in `mobile/`, `npm test` in `app/`, and `openspec validate phone-data-viewer --strict --no-interactive`; verify all pass.
- [ ] 4.2 `/save`, deploy the branch's server to staging, then run the iPhone device check on the saved commit with the *Places data* scenarios and the health empty state; verify `result=works`, and list the health check on a real iPhone as left for the person.
