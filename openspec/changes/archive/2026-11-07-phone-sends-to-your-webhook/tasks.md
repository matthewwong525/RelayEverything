# Tasks

## 1. Before the build

- [x] 1.1 Check *Share to Relay Everything* is live on `main`, then bring this branch up to date; read its share sheet code (`ShareSettings`, `ShareInbox.swift`) and correct design.md *The share sheet and Shortcuts* if its flag or inbox differs

## 2. Format (worker)

- [x] 2.1 `format.ts`: add the `note.file` envelope (design.md *The phone builds v1 at send time*) and widen the `device.id` and sample and point `id` descriptions; `format.test.ts`: a `note.file` passes `message`, and the server's builders never make one
- [x] 2.2 `format.test.ts`: parse each `mobile/test/fixtures/webhook/*.json` with `message` and check its headers with the server's signature check and the fixtures' fixed secret
- [x] 2.3 Run `npm run relay:api-doc` in `app/` so `site/public/webhooks/v1.schema.json` lists `note.file`

## 3. Phone: settings, store and sender

- [x] 3.1 `data/settings.dart`: add `place` (`server` default, `webhook`), encoded and decoded, old saved settings read as `server`; tests for each
- [x] 3.2 `data/connection.dart` `KeyVault`: keep the webhook address and secret in secure storage, read, write and clear; an address check (`https://` only, no user name or password, private hosts allowed); tests for each refusal and a home address
- [x] 3.3 `data/store.dart`: an install id and an id counter in `state`; `queuePoints` and health queueing write ids into each body; `moveOutbox(destination)` updates every waiting row in one step; `enqueue` uses the current place; tests
- [x] 3.4 New `data/webhook.dart`: `WebhookClient` builds each v1 envelope from the outbox bodies, makes a `whsec_` secret, signs by Standard Webhooks with `crypto`, sends with a stable `webhook-id`, and maps answers (design.md *Answers*); `test()` sends `webhook.test`; tests against a fake HTTP client, and a test that writes the fixtures in `mobile/test/fixtures/webhook/`
- [x] 3.5 `data/sender.dart` and `data/outbox.dart`: `Sender.api` returns the client for the current place; `flush` picks the client by each item's `destination`, keeps order, and follows design.md *Answers* in webhook mode while server mode keeps its rules; extend `outbox_test.dart` for both places, a 503 kept, a 413 file dropped, a 400 kept
- [x] 3.6 `controller.dart` and `sync/background.dart`: pass the place through every round; in webhook mode a round runs with no key kept (`backgroundSync` today stops when `KeyVault` has no connection); switching place moves the outbox and asks the earlier-notes question for the new place; turning sending off works the same in both places; tests

## 4. Phone: screens

- [x] 4.1 `screens/connect.dart`: *Where should the phone send?* with the two places; *My own webhook* shows the address, the secret with *Copy*, *Send a test* with the answer, and *Save*; *Relay Everything* keeps today's flow; widget tests for save, a refused address, and a test answer
- [x] 4.2 `screens/settings.dart`: *Send my notes* with the place line, the *Webhook* row and *Send a test* in webhook mode, the last failure line, and the *Stop sending?* words for both places; widget tests
- [x] 4.3 Share sheet: write `ShareSettings` off in webhook mode so the extension saves items for the app; a Swift or Dart test that a shared item in webhook mode reaches the outbox, not the server

## 5. Website and wiki

- [x] 5.1 `site/public/webhooks/receiver.mjs` saves a `note.file` beside its note; `site/src/content/docs/connections/your-database.md` adds *Send from the phone* (set up, the `note.file` message, what you give up); update `app/settings.md`, `privacy.md` and `start/connect-a-phone.md`
- [x] 5.2 `wiki/relay-spaces.md` *Webhooks*: one line that the phone can send v1 itself, linking `mobile/lib/data/webhook.dart`

## 6. Checks

- [x] 6.1 Run `flutter test` in `mobile/`, the app tests in `app/`, `scripts/product-name.test.mjs` and `node scripts/public-check.mjs`
- [x] 6.2 Run `site/public/webhooks/receiver.mjs` behind an `https://` tunnel, set it on a phone build in webhook mode, and send a note with a file, health and places; check the receiver saved each one and no request reached the server
- [x] 6.3 `/save`, then check the Android file from the run and the website preview (`node scripts/publish-relay-site.mjs --ref HEAD --staging`)
