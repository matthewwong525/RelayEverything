# Tasks

## 1. Phone data and sending

- [x] 1.1 In `mobile/lib/data/store.dart`, give `earlierCount` and `queueEarlier` a `fromWebhook` option that adds own notes (`mine = 1`) with `server_id IS NULL`, `sent_at IS NOT NULL`, no pending words or pin, and not being deleted; verify with new `store_test.dart` cases: a webhook-sent note counts and queues only with `fromWebhook`, and a note with a server id never does.
- [x] 1.2 In `mobile/lib/relay.dart` and `mobile/lib/controller.dart`, add `SendPlace? privateTo` to `startSending` (one `copyWith`, one `_moveOutbox`), and pass `fromWebhook` from `earlierNotes({SendPlace? to})` and `startSending` when the current place is `webhook` and the new one is `server`; update `test/fakes.dart`; verify with `controller_test.dart` cases: from whole-webhook mode, `startSending(place: server, privateTo: webhook)` sends waiting notes to the server and health and calendar to the webhook, keeps the calendar's sent list, and `sendEarlier` queues the webhook-sent notes oldest first.

## 2. Phone screens

- [x] 2.1 In `mobile/lib/screens/connect.dart`, add a `signInOnly` flag that hides *Send to my own webhook instead*; verify with a `screens_test.dart` case.
- [x] 2.2 In `mobile/lib/screens/folder.dart`, give `choosePlace` a `keepWebhook` option that opens `ConnectScreen(signInOnly: true)`, asks `_EarlierDialog` with the webhook wording (*They are not on Relay Everything yet.*), and starts sending with `privateTo: webhook`; it returns whether it signed in. Verify with `screens_test.dart` cases for the dialog text and a closed sign-in that changes nothing.
- [x] 2.3 In `mobile/lib/screens/account.dart`, replace *Notes from elsewhere* with *Sign in to Relay Everything* and its subtitle, take a `scanner` from Settings, and show the `SnackBar` after a sign-in from this row; update the class's doc comment. Verify with `screens_test.dart`: the webhook page shows the row and no *Notes from elsewhere* (replacing the test near line 2107), and signing in lands on the signed-in page with *Only my own webhook* picked and the message shown.
- [x] 2.4 In `mobile/device-check/flows/settings.yaml`, after the Sign in screen, open *Send to my own webhook instead*, type `https://example.com/hook`, *Save*, answer the earlier-notes question if shown, open the Account row, and assert *Sign in to Relay Everything* with a screenshot; verify the flow file parses with the device check's own lint, if it has one.

## 3. Docs

- [x] 3.1 Update `mobile/README.md`'s Account page bullet and `site/src/content/docs/app/settings.md` (the webhook Account page paragraph and the *Only my own webhook* section) for the new row, what signing in keeps, the earlier-notes question and adding the webhook on the page; verify `node scripts/product-name.test.mjs` passes and no page still names *Notes from elsewhere*.

## 4. Checks

- [x] 4.1 Run `flutter analyze` and `flutter test` in `mobile/`, and confirm both are clean.
- [x] 4.2 Run `/save`, and confirm CI's phone checks pass and the iPhone device check shows the webhook Account page with *Sign in to Relay Everything*.
