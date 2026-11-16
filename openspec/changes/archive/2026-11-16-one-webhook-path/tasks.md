# Tasks

## 1. One destination on the phone

- [x] 1.1 `mobile/lib/data/settings.dart`: remove `privateTo` and `privatePlace` from `Settings`, its `copyWith`, `encode` and `decode`; add `Settings.hadPrivateWebhook(saved)`, true when the saved JSON has `privateTo: "webhook"` and `place` is not `webhook`.
- [x] 1.2 `mobile/lib/data/store.dart`: `moveOutbox(destination)` with one destination; when a kept `outbox.private` differs from it, drop the calendar's sent list and the sent times of health, points and the calendar; remove `outbox.private`; every row takes `destination`. Enqueue no longer routes private routes apart. Keep the point id fill.
- [x] 1.3 `mobile/lib/data/sender.dart` and `mobile/lib/data/outbox.dart`: remove `privateApi` and the `private` split in `flush`.
- [x] 1.4 `mobile/lib/controller.dart` and `mobile/lib/sync/background.dart`: one flush per round and photos through `api`; remove `_privateApi`, `privateWebhookMissing`, `setPrivatePlace` and `startSending(privateTo:)`. In `load`, when `Settings.hadPrivateWebhook(saved)` and sending is on, set the store key `notice.throughServer` before the settings save; call `moveOutbox` when `outbox.private` exists or `outbox.destination` differs.
- [x] 1.5 `mobile/lib/relay.dart` and `mobile/lib/web/web_relay.dart`: remove the same members; add `throughServerNotice` and `dismissThroughServerNotice()`.

## 2. Screens and words

- [x] 2.1 `mobile/lib/screens/webhooks.dart`: remove the *Health, places, calendar and photos* group and its setup; new first line, as design.md *Words* says.
- [x] 2.2 `mobile/lib/screens/connect.dart`: remove `privateOnly` and its words; new `signInOnly` words. `mobile/lib/screens/folder.dart`: remove `keepWebhook` and `_toWebhook`; folder pages say *Sent*. Update the callers in `account.dart`, `connect_ai.dart` and `email_notes.dart`.
- [x] 2.3 `mobile/lib/screens/account.dart`: the webhook Account page's *Sign in to Relay Everything* line and the message after sign-in, as design.md *Words* says.
- [x] 2.4 `mobile/lib/screens/home.dart`: the one-time *Everything now goes through Relay Everything* dialog with *OK* and *Open Webhooks*, shown after the first frame while `throughServerNotice` is true; each way out clears it.

## 3. Tests

- [x] 3.1 `mobile/test/store_test.dart`: `moveOutbox` from a store with `outbox.private` set to `webhook` moves health, points and calendar rows to `relay-server` in order, drops the calendar's sent list, and removes the key.
- [x] 3.2 `mobile/test/controller_test.dart`: an old saved JSON with `privateTo: webhook` loads as server-only, sets the notice once, and a round sends health, points, calendar and photos only to the fake server, none to the fake webhook; a signed-in phone with a webhook kept sends nothing to it. Remove the private-place tests.
- [x] 3.3 `mobile/test/sync_test.dart` and `health_test.dart`: one flush per background round; remove the private-client cases.
- [x] 3.4 `mobile/test/screens_test.dart`: *Webhooks* signed in shows no switch; the webhook Account page and *Sign in* show the new words; the dialog shows once, *Open Webhooks* opens *Webhooks*, and *OK* clears it. Remove the private-switch tests; update `narrow_test.dart` and `web_settings_test.dart`.
- [x] 3.5 `mobile/device-check/flows/settings.yaml`: drop any step that taps *Only to my own webhook*.

## 4. Docs and the website

- [x] 4.1 `AGENTS.md` *Health and location data*: signed in, the site gets them and sends them on only to ticked webhooks; a phone with no account sends them only to its own webhook.
- [x] 4.2 `mobile/README.md`, `wiki/relay-phone-sync.md`, `wiki/relay-webhook-changes.md`: remove the second place.
- [x] 4.3 Website: `site/src/content/docs/app/settings.md`, `health.md`, `location.md`, `calendar.md`, `photos.md`, `on-a-computer.md`, `shortcuts.md`, `your-notes.md`, `share.md`, `privacy.md`, `health-privacy.md`, `connections/your-database.md`, `start/connect-a-phone.md`: remove *Only to my own webhook*; say signed in, everything goes through Relay Everything, and to keep data off the server, use no account and your own webhook.

## 5. Checks

- [x] 5.1 `flutter analyze` and `flutter test` in `mobile/`; `node scripts/product-name.test.mjs`; `grep -rn "privateTo\|Only to my own\|Only my own" mobile/lib site/src AGENTS.md` finds nothing.
- [x] 5.2 If `recordings-as-attachments` landed first, check that the server → webhook send and the no-account phone → webhook send both carry a recording as a file with its transcript, and that this change left both as that plan made them; if this lands first, leave a note on that plan.
- [x] 5.3 If `recently-deleted` landed first, check that the server → webhook send and the no-account phone → webhook send both carry `note.deleted` and `note.recovered`, and that this change left both as that plan made them; if this lands first, leave a note on that plan.
- [x] 5.4 `/save`, then the iPhone device check on the saved commit: *Webhooks* signed out, the webhook Account page and *Sign in* words.
