# Tasks

## 1. Pull when sending to the server starts

- [x] 1.1 In `mobile/lib/controller.dart` `startSending`, when the place is `SendPlace.server`, set `_pull ??= Completer<void>()` before `_syncAfter()`, with a one-line comment; verify `flutter analyze` is clean
- [x] 1.2 In `mobile/test/note_sync_test.dart`, add a test: a saved key with sending off, then `startSending(place: SendPlace.server)` and `settled()`, sends the outbox and then makes one `GET /apps/relay/api/notes`, and lists the pulled note; verify it fails before 1.1 and passes after
- [x] 1.3 Add a test that `startSending(place: SendPlace.webhook)` makes no notes read; verify it passes
- [x] 1.4 Update the *Sync* line of the Mac app in `mobile/README.md` to name sign-in; verify the line reads right
- [x] 1.5 Review fix: in `startSending`, ask for the pull in the round after the one running (`pullNotes()`, or `running.then((_) => pullNotes())`), so a running round whose notes part does not empty can not end it unread; add a test where sign-in comes while a webhook round runs and its notes do not all go, and it still makes one `GET notes` after the `POST notes`; verify it fails before the fix and passes after
- [x] 1.6 Review fix: in the sign-in test in `mobile/test/note_sync_test.dart`, expect a `POST notes` before the order check, so the check can not pass with no POST; verify it passes

## 2. Website

- [x] 2.1 In `site/src/content/docs/start/connect-a-phone.md` step 6, say the app sends its notes and gets your notes from your other devices at once; in `site/src/content/docs/app/on-a-computer.md` *The Mac app*, say the Mac gets your notes when you sign in; verify `node scripts/product-name.test.mjs` passes

## 3. Checks

- [x] 3.1 Run `flutter test` in `mobile/` and verify all tests pass
