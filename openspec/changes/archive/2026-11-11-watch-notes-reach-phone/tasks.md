# Tasks

## 1. Watch: record on open, save on leave, show where the note is

- [x] 1.1 In `mobile/ios/RelayWatch/WatchModel.swift`, drop `.main`; add `.idle` and `.notSaved`; add `lastSaved`; `save()` goes to `.notSaved` only for a failed save of 1 s or longer; `cancel()` goes to `.idle`. Move the screen rules that need no hardware (which screen after save, cancel, failure, short recording; the Saved screen's iPhone words) into a plain type in `WatchNotes.swift` so `RelayWatchTests` builds them in. Verify: new `RelayWatchTests` cases for each rule pass in the `watch-tests` CI job.
- [x] 1.2 In `RelayWatchApp.swift`, start `talk()` on `scenePhase` `.active` after `.background` or at first launch, and `save()` on `.background`; `.inactive` changes nothing. Verify: a test of the phase rule (in the plain type from 1.1) passes; the app compiles in CI.
- [x] 1.3 In `WatchScreens.swift`, remove `MainScreen`; add the idle screen (*Tap to record*), the not-saved screen (*Not saved*, *Tap to record again*), the Saved screen's live iPhone line and *Tap for a new note*, the waiting line on the recording screen; the microphone screen loses its OK. Update `StartVoiceNoteIntent` text if it names *Talk*. Verify: CI compiles; `grep -n "Talk" mobile/ios/RelayWatch` finds no user text naming a Talk button.
- [x] 1.4 In `WatchLink.swift`, after a send and at `onReady` with notes waiting, send the wake message when `isReachable`. Add `send` wake to the `WatchSender` fake in the tests. Verify: a `RelayWatchTests` case shows a wake after a send when reachable and none when not.

## 2. iPhone: answer the wake, keep a watch note with no words

- [x] 2.1 In `mobile/ios/Runner/RelayWatchReceiver.swift`, add `session(_:didReceiveMessage:)` as a no-op. In `ShortcutsInbox.keepWatchRecording`, write `"from": "watch"` in the request. Verify: `RunnerTests/ShortcutsInboxTests.swift` asserts the field; it runs in the device check's `swift-tests` job.
- [x] 2.2 In `mobile/lib/shortcuts/inbox.dart`, read `from` into `InboxRequest.fromWatch`; in `mobile/lib/controller.dart` pass it through `keepRecording` onto the note (stored with the note's body, or a nullable column with a migration if the body is not read back). Verify: a `shortcuts_test.dart` case drains a watch request and the kept note is marked from the watch, also after a store reopen.
- [x] 2.3 In `_write`, keep a watch note with no words: words no longer pending, a no-words mark, the recording kept, nothing queued to send, no *Nothing was saved* notice. A held voice note with no words is still dropped. Verify: two `controller_test.dart` cases (watch kept, held dropped) pass.
- [x] 2.4 In `mobile/lib/screens/timeline.dart`, show *No words heard* as the subtitle of such a note, with no *Try again*. Verify: a `screens_test.dart` case finds *Voice note* and *No words heard*, and no *Try again*.

## 3. Words for people

- [x] 3.1 Update `mobile/README.md` and `site/src/content/docs/app/voice-notes.md`: the app records when it opens, a tap or leaving saves, the *X* keeps nothing, the watch shows *On your iPhone*, and a watch note with no words stays as *No words heard*. Verify: `node scripts/product-name.test.mjs` passes; the page names no Talk button.

## 4. Checks

- [x] 4.1 Run `cd mobile && flutter analyze && flutter test`; all pass.
- [x] 4.2 `/save`, then confirm CI builds the signed iPhone app with the watch app and `watch-tests` passes.
