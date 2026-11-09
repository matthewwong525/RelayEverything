# Tasks

## 1. Phone data: two places at once

- [x] 1.1 `mobile/lib/data/settings.dart`: add `privateTo` (`SendPlace`, default `server`) to the constructor, `copyWith`, `encode` and `decode`, and a `privatePlace` getter (`webhook` when `place == webhook`, else `privateTo`). Verify in `data_test.dart`: old saved settings read `privateTo: server`; a round trip keeps `webhook`; `privatePlace` in all four combinations.
- [x] 1.2 `mobile/lib/data/store.dart`: the `outbox.private` state key; `enqueue` takes it for `health`, `locations` and `calendar` and `outbox.destination` for the rest, in the same statement; `moveOutbox(notes, private)` sets both and moves each group's rows in one transaction, dropping the calendar's sent list when the private destination changes; a missing `outbox.private` reads as `outbox.destination`. Update every caller. Verify in `store_test.dart`: a health row and a note row queued with different places get different destinations; a move of only the private place leaves note rows and drops `calendar_sent`; an old store with no key behaves as today.
- [x] 1.3 `mobile/lib/data/outbox.dart`: `flush` lists only `api.destination`'s rows and still stops at a row gone or moved since the list. Verify in `sync_test.dart`: with a note for the server and health for the webhook waiting, a server flush sends the note and leaves the health row; a webhook flush does the reverse; a 503 from the webhook leaves the server's rows untouched.
- [x] 1.4 `mobile/lib/data/sender.dart`: `privateApi`, which never returns `RelayApi` while `privateTo == webhook`, and returns null when the webhook or install id is missing. Verify in `sync_test.dart` for each combination of place, choice, key and webhook.

## 2. Phone rounds and controller

- [x] 2.1 `mobile/lib/controller.dart` and `relay.dart`: `setPrivatePlace(SendPlace)` (saves the setting, calls `moveOutbox`, starts a round), `privateWebhookMissing`, and `_sync` flushing the notes client then the private client when it differs, with photos through the private client and `keepGoing` checking both places; `load()` keeps sending on when only the private webhook is missing. Update the test fake in `fakes.dart`. Verify in `controller_test.dart`: with the choice on, a note reaches the fake server and health, points, calendar and a photo reach the fake webhook, and the fake server gets no `health`, `locations`, `calendar` or `photos` request; a webhook 503 still lets notes sync; switching back sends the waiting health to the server; *Sign out* keeps `privateTo` and the webhook.
- [x] 2.2 `mobile/lib/sync/background.dart`: `backgroundRound` builds both clients from the saved settings, flushes both, sends photos through the private one, returns true only when both finished, and pulls notes after the notes flush only. Verify in `sync_test.dart` with a background round: the same split as 2.1, and a missing webhook leaves private rows waiting with nothing private sent to the server.

## 3. Phone screens

- [x] 3.1 `mobile/lib/screens/account.dart`: the *Health, places, calendar and photos* group on the signed-in page, between *Connections* and the page link: *Relay Everything* and *Only my own webhook* as a `RadioGroup`, the line that data already sent stays on the page, and with the webhook picked its host, *Send a test* and the last failure; *Set your webhook again* when `privateWebhookMissing`. No filled button. Verify in `screens_test.dart`: the group's rows signed in; no group in webhook mode or signed out; the picked state; the missing state.
- [x] 3.2 `mobile/lib/screens/connect.dart`: open the webhook form in a private mode from 3.1, whose *Save* keeps the webhook and sets `privateTo: webhook` without starting whole-webhook sending or asking about earlier notes, and whose back button changes nothing. Verify in `screens_test.dart`: pick with no webhook kept → form → *Save* → the Account page shows it picked and `settings.place` is still `server`; back from the form leaves *Relay Everything* picked.
- [x] 3.3 `mobile/lib/screens/folder.dart`: *Health*, *Location*, *Calendar* and *Photos* say *Sent to your webhook* with the time when `privatePlace == webhook`. Verify in `screens_test.dart`, and add the Account page with the group to `narrow_test.dart` at 360 px.

## 4. Docs

- [x] 4.1 `mobile/README.md` (the Account page and the private choice) and `wiki/relay-phone-sync.md` (two places, two flushes, never a fallback). Verify the links resolve with the wiki's link check.
- [x] 4.2 Website: `site/src/content/docs/app/settings.md`, `app/health.md`, `app/location.md`, `app/calendar.md`, `app/photos.md`, `privacy.md` and `health-privacy.md` explain *Only my own webhook*, what stays on the page, and what the person gives up. Never name the private site's address. Verify with `node scripts/product-name.test.mjs`.
- [x] 4.3 `AGENTS.md` and its `CLAUDE.md` copy, *Health and location data* line: a signed-in phone may send health and places only to its own webhook, and then never to the site. Verify the two files match.

## 5. Checks

- [x] 5.1 `flutter analyze` and `flutter test` in `mobile/`; `node scripts/product-name.test.mjs`; `node scripts/public-check.mjs`. All pass.
- [ ] 5.2 `/save`, then the iPhone device check on the saved commit with a scenarios file in a temporary folder: the fixed tour passes and the signed-out Account path is unchanged. The signed-in group needs an account the check doesn't have, so 3.1 to 3.3's widget tests cover it.
