# Tasks

## 1. Watch app (`mobile/ios/RelayWatch/`)

- [x] 1.1 Add the `RelayWatch` watchOS 10 SwiftUI target to `Runner.xcodeproj`, embedded in Runner with *Embed Watch Content*; bundle id `com.matthewwong525.relayApp.watchkitapp`; version and build from Runner's Flutter settings; brand colors and Inter font.
- [x] 1.2 Main screen: amber *Talk* button and the grey wait count; recording screen with time, sound bars, tap-anywhere save and *X*; *Saved* screen; microphone-refused screen.
- [x] 1.3 Recorder: 16 kHz mono 16-bit WAV, metering for the bars, under 1 s keeps nothing, stop and save at 5 min, haptic on save.
- [x] 1.4 Queue: keep each saved note in `watch-queue/` with its id, created time and length; send with `WCSession.transferFile`; delete only on the iPhone's `kept`; on launch, send again any note with no transfer in flight.
- [x] 1.5 `RelayWatchWidget` WidgetKit target (circular, corner, inline) opening `relay-watch://record`; `onOpenURL` starts recording.
- [x] 1.6 `StartVoiceNoteIntent` App Intent and `AppShortcutsProvider` for the Action button.
- [x] 1.7 `RelayWatchTests`: queue keeps a note until `kept`, never sends one id twice, survives a reload; recorder length rules.

## 2. iPhone receiver (`mobile/ios/Runner/`, `mobile/lib/`)

- [x] 2.1 Move the inbox JSON writer out of `RelayIntents.swift` into `ShortcutsInbox.swift`; `RelayIntents.swift` uses it with no change in output.
- [x] 2.2 `RelayWatchReceiver.swift`: activate `WCSession` in `AppDelegate`; on a file, check the id, move it to `shortcuts-inbox/<id>/voice.wav`, write `<id>.json`, answer `kept`; post `inboxChanged` on the method channel when Flutter runs.
- [x] 2.3 Dart: drain the inbox on `inboxChanged` and on resume, not only at start; one drain at a time.
- [x] 2.4 Tests: a Swift test that a received file becomes the same JSON and WAV `RelayIntents.swift` writes, and a bad id is refused; a Dart test that a resume drain keeps a watch note once with its created time and no place.

## 3. Builds (`mobile/ios/fastlane/`, `.github/workflows/`)

- [x] 3.1 `Fastfile`: `SIGNED_TARGETS` gains the watch app and its widget; a private lane registers a missing bundle id with the App Store Connect key before the profiles.
- [x] 3.2 `mobile-ios.yml` and `mobile-device-check.yml`: run `RelayWatchTests` on a watch simulator beside the Swift tests.

## 4. Docs

- [x] 4.1 `mobile/README.md`: an *Apple Watch* bullet in *What it does*, and the new bundle ids in *Builds on GitHub*.
- [x] 4.2 `site/src/content/docs/app/voice-notes.md`: a *From your Apple Watch* section; check `scripts/product-name.test.mjs` passes.
- [x] 4.3 `wiki/development/device-check.md`: say the Swift tests include the watch tests.

## 5. Checks

- [x] 5.1 `flutter analyze` and `flutter test` in `mobile/`; `node scripts/product-name.test.mjs`; `node scripts/public-check.mjs`.
- [x] 5.2 `/save`: the branch's Mobile CI builds and signs the iPhone app with the watch app, and the Swift and watch tests pass.

## 6. Review fixes

- [x] 6.1 Watch queue: handle `session(_:didFinish:error:)`; mark a note delivered after a transfer with no error, or back to not sent after a failed one; still delete the recording on `kept`. After a saved note, send only notes never sent or whose transfer failed (6.4 owns the launch rule). `RelayWatchTests`: a failed transfer goes again.
- [x] 6.2 `mobile/test/shortcuts_test.dart`: one test where only `inboxChanged` keeps the watch note; one where `inboxChanged` during a drain makes the follow-up drain keep a note that came meanwhile.
- [x] 6.3 `mobile/README.md` *Release the app* step 1: the App Store page needs Apple Watch screenshots too.
- [x] 6.4 Lost transfers: `RelayWatchReceiver.swift` keeps the last 500 watch note ids it took in `watch-received.json`, written before `kept`, and for a repeat id answers `kept` and writes nothing; the watch, at launch and when the session is ready, sends again every note with no transfer in flight and no `kept`; a failed `didFinish` goes at the next saved note or launch. `RelayWatchTests`: a note on its way but not in flight at a reload is sent again; `RunnerTests`: a repeated id writes nothing and still answers kept.
