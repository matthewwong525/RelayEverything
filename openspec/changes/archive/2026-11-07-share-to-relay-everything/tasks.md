# Tasks

## 1. Shared rules and the phone side (Dart)

- [x] 1.1 Check that `apple-shortcuts-and-attachments` is archived on `main` (files on notes, `keepNote(text, files:)`, the `attachment` outbox route); stop and report if not.
- [x] 1.2 Add `lib/share/draft.dart`: words, then shared text, then link; files past 10 or over 25 MB left out with a reason; nothing left and no words means no *Save*. `test/share/share_test.dart` covers the six rows of the proposal's table.
- [x] 1.3 Use the shipped `RelayController.keepNote(pin: false)`, which skips the pin even with *Pin notes* on; controller test shows no location call.
- [x] 1.4 Add `mobile/test/fixtures/shared-note.json` and a test that `LocalNote.toJson` for a note with two files equals it.
- [x] 1.5 Move the key to the App Group's Keychain group, service `relay.shared`, in `KeyVault.upgrade` (write new, read back, delete old; `forget` deletes both; no App Group keeps the old group; Android never moves); tests with a group-aware fake storage, including a stop between write and delete.
- [x] 1.6 Mirror `{sending}` (on only with a key) to the App Group through `relay/files` `setShareSettings` (`ShareGroup.setSending`) on load and on each settings, connect, sign-in, server and disconnect change; controller test with a fake share group shows each call and that no key is in it.
- [x] 1.7 Add `lib/share/inbox.dart` and drain it on load, on resume (`RelayController.resume`) before sync, and in `backgroundRound` in `sync/background.dart`: files into `attachments/`, note with no pin, `sentNote` and `sentFiles` respected, only unsent files queued, only while sending is on, a malformed entry moved to `.bad/`; tests for sent, half-sent, unsent with sending off, and malformed.

## 2. iPhone share extension (Swift)

- [x] 2.1 Add the `ShareExtension` target to `Runner.xcodeproj` (bundle ID `com.matthewwong525.relayApp.share`, iOS 15, embedded in Runner), its `Info.plist` with the activation rule and the display name *Relay Everything*, and the App Group (also the Keychain group) in both targets' entitlements; `flutter build ios --simulator` passes on the Mac check.
- [x] 2.2 Add `relay/files` methods `setShareSettings` and `appGroupPath` to `RelayChannels` in `ios/Runner/RelayBackground.swift`.
- [x] 2.3 Add `ShareNote.swift` (the same rules as `draft.dart`, and the note body), `SharedItems.swift` (items to a draft, files copied into the group at once) and `ShareInbox.swift` (write in `.tmp-<id>`, rename, update sent marks).
- [x] 2.4 Add `ShareSender.swift`: reads settings and key, sends nothing unless sending is on and a key exists, posts the note then each file from disk, one 20-second deadline, marks each success in `note.json`.
- [x] 2.5 Add `ShareViewController.swift` with the SwiftUI card and its states from the design's UX section: shared items, *Add words*, left-out line, foot line, *Sending…*, *Sent*, *Kept…*; *Cancel* deletes the draft's copied files.
- [x] 2.6 Add `RunnerTests` for the Swift note body against `shared-note.json` and the six draft cases, and run them in `.github/workflows/mobile-device-check.yml`.
- [x] 2.7 Add a device-check flow in `mobile/device-check/flows/` that shares a link from Safari on the simulator into Relay Everything with sending off and sees the note in the app's timeline.

## 3. Android share target (Kotlin and Dart)

- [x] 3.1 Add `ShareActivity.kt`, a see-through theme, and its manifest entry with the `SEND` and `SEND_MULTIPLE` filters; it copies `content://` items to `cacheDir/shared/` and answers `relay/share`; `flutter build apk` passes in `mobile-android.yml`.
- [x] 3.2 Add `lib/share/share_main.dart` (`@pragma('vm:entry-point') shareMain`) and `lib/share/share_card.dart`: *Save* adds the note with files and `pin: false`, waits for its sync up to 20 seconds, then closes; widget tests for sending on, sending off, offline, and a left-out file.

## 4. Website

- [x] 4.1 Write `site/src/content/docs/app/share.md` (*Share from any app*: iPhone and Android steps, what each item becomes, the limits, sending off and on) and link it in the docs sidebar (`site/sidebar.mjs`); add it and the extension's `Info.plist` to `scripts/product-name.test.mjs`.
- [x] 4.2 Update `site/src/content/docs/app/your-notes.md` and `site/src/content/docs/privacy.md`: shared notes have no place, and the card sends only while sending is on.

## 5. Checks

- [x] 5.1 Run `flutter test` and `flutter analyze` in `mobile/`, `node scripts/public-check.mjs`, and `node scripts/product-name.test.mjs`; all pass.
- [x] 5.2 `/save`, then check that CI's Android build and the iPhone device check pass, with the share flow's pictures.
- [x] 5.3 Preview the website with `node scripts/publish-relay-site.mjs --ref HEAD --staging` and check the *Share from any app* page.
