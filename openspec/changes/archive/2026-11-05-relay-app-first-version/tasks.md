# Tasks

## 1. This computer

- [x] 1.1 Install Flutter stable, Android command-line tools (platform 35, build-tools) and OpenJDK 17; `flutter doctor` passes for Android

## 2. Server (app/worker/apps/relay, schema)

- [x] 2.1 Add the migration for `relay_devices`, `relay_notes`, `relay_health`, `relay_locations`, and seed rows in `schema/seed.sql`
- [x] 2.2 Create R2 buckets `relay-ring-notes` and `relay-ring-notes-staging` and bind `RELAY_BUCKET` in `app/wrangler.jsonc` (production and staging)
- [x] 2.3 Write the `pebble` handler (version, timestamp, HMAC, dedupe, test events, audio to R2) and its tests, including Pebble's documented signing example
- [x] 2.4 Write the `notes`, `health`, `locations`, `timeline`, `summary` and audio handlers, place resolution, and their tests
- [x] 2.5 Let unrevoked Relay device tokens reach only Relay's device routes (core exception if needed), with tests for allowed, other-route and revoked cases

## 3. Device keys (scripts)

- [x] 3.1 Write `scripts/relay-device-key.mjs` (create, list, revoke; production and staging) and its tests for the parts that do not call Cloudflare
- [x] 3.2 Declare `RELAY_PEBBLE_SIGNING` as a saved key the relay app lists, and the App Store Connect names in `.env.example`

## 4. Site page (app/src/apps/relay)

- [x] 4.1 Build `App.tsx` and `app.json`: summary, timeline with audio, places, *Set up a phone* and *Pebble webhook* dialogs, release and TestFlight links; with tests

## 5. Phone app (mobile/)

- [x] 5.1 Create the Flutter project, store, API client and outbox, with unit tests
- [x] 5.2 Build the timeline, compose, settings and connect screens, with widget tests
- [x] 5.3 Add health sync (HealthKit, Health Connect) and location pin plus background history, with permission texts and unit tests for the sync logic
- [x] 5.4 Rewrite `mobile/README.md` for the public repository: what Relay is, how to build, how to point it at a server

## 6. Builds and publishing

- [x] 6.1 Add `mobile/.github/workflows/` `ci.yml`, `android.yml`, `ios.yml` and the fastlane setup
- [x] 6.2 Extend `scripts/publish-relay-app.mjs` with Apple signing files and `--branch`, with tests
- [x] 6.3 Update `AGENTS.md`'s Relay section: device keys, the pre-publish branch build, where health and location live

## 7. Review fixes

- [x] 7.1 Refuse a service token that is neither a device nor the checker, named per environment by the SHA-256 in `RELAY_CHECKER_SHA256`; tests, design and the device-keys spec
- [x] 7.2 Ask for location once, right after the phone connects, with *Pin notes to a place* kept on; test
- [x] 7.3 Summary takes the largest source per device for steps and sleep; test with a phone and its watch
- [x] 7.4 Ask for Health Connect's background read in `allow()` on Android
- [x] 7.5 Keep a typed note at once, and add its pin when the phone has a fix; test
- [x] 7.6 Answer one `Range` of a recording with 206 and `Content-Range`; test
- [x] 7.7 Page the timeline on time and id, on the server, the site page and the phone; test with two notes at one time
- [x] 7.8 Setup steps say *Open the Relay app and tap Scan the QR code*, on the site page and the key page; tests
- [x] 7.9 The check before publishing fails, naming `RELAY_CHECKER_SHA256`, `app/wrangler.jsonc` and the new fingerprint, when the checker policy's token Client ID's SHA-256 differs from that environment's var; tests
- [x] 7.10 A typed note with pins on gets its upload only when its pin is found or the phone gives up, so no sync sends it without its place; test with a second note syncing while the first waits

## 8. Verification

- [x] 8.1 Run the local checks, `node --test scripts/*.test.mjs`, and `flutter analyze` and `flutter test` in `mobile/`
