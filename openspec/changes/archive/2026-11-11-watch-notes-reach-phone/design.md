# Design

## Context

The watch app (archive `2026-11-10-apple-watch-voice-notes`) records a 16 kHz mono WAV, queues it in `watch-queue/`, and sends it with `WCSession.transferFile`. The iPhone's `RelayWatchReceiver.swift` moves it into `shortcuts-inbox/<id>/` and answers `kept` with `transferUserInfo`; the watch then deletes its copy. Dart drains the inbox at load, on resume and on `inboxChanged`, through `keepRecording`, and `_write` writes the words.

The person reports watch notes never show on the phone, and the watch shows no note waiting. So `kept` came back: the phone wrote the inbox. In Dart the only path that removes such a note with no action by the person is `_write`: `words.isEmpty` → `store.dropNote` and the notice *No speech heard. Nothing was saved.* So the recordings most likely reached the phone and gave no words (silent, too quiet, or cut short). This can't be proved on this computer: there is no watch.

## Goals / Non-Goals

**Goals:** record on open; save on leave; show where a note is; never lose a watch note on the phone; deliver faster when near.

**Non-Goals:** a background keep on the phone with the app closed; a change to held voice notes; a watch notes list.

## Decisions

### Record on open, save on leave (watch)

- `WatchModel.Screen` loses `.main`; it is `.recording`, `.saved`, `.notSaved`, `.microphoneRefused`, plus `.idle` for the instant before recording starts.
- `RelayWatchApp` reads `@Environment(\.scenePhase)`. On `.active` when the last phase was `.background` (or first launch), `model.talk()`. On `.background`, `model.save()` if recording. `.inactive` (wrist down, Always On) changes nothing, so a short wrist drop keeps recording.
- `onOpenURL` and `StartVoiceNoteIntent` still call `talk()`; `talk()` already ignores a call while recording, so open plus URL starts one recording.
- After a tap save, the screen stays on *Saved*; a tap there calls `talk()`. The 1 s return to the main screen goes.
- `save()` that gets nil from `recorder.stop()` or a throw from `queue.add` goes to `.notSaved` when the recording was 1 s or longer, and to `.saved`-less `.idle` with no message when it was shorter (a quick open and close is not an error). `.notSaved` shows *Not saved*, *Tap to record again*.
- *Microphone refused*: its OK goes; the screen stays until the person allows it and comes back, when `talk()` checks again.
- Alternative: keep a `Talk` screen as a fallback after save. Rejected: the person asked for no Talk screen.

### Show where the note is (watch)

`WatchModel` keeps `lastSaved: String?` (the id). The Saved screen shows *Sending to your iPhone* while that id is in `queue.notes`, and *On your iPhone* once `onKept` removes it. Below, `waitingWords(waiting - (lastSaved waiting ? 1 : 0))` shows other notes that wait. The recording screen shows the same waiting line under *Tap to save* when any wait.

### Wake the iPhone (watch and iPhone)

After `transferFile`, when `WCSession.default.isReachable`, the watch calls `sendMessage(["wake": true], replyHandler: nil, errorHandler: nil)`. From a foreground watch app this launches the iPhone app in the background; once its session activates, the queued transfer is delivered at once. `RelayWatchReceiver` implements `session(_:didReceiveMessage:)` as a no-op. The same wake goes at `onReady` when notes wait. No audio goes by message: messages are small, and `transferFile` keeps the queue's guarantees.

### Keep a watch note with no words (phone)

- `ShortcutsInbox.keepWatchRecording` adds `"from": "watch"` to the request JSON. `_requestOf` reads it into `InboxRequest.fromWatch`; `keepRecording` takes `fromWatch` and stores it on `LocalNote` as a JSON field in the note's stored body (`toJson`/`fromJson`), with no new column. The builder confirms the body round-trips; if the store reads notes from columns only, a migration adds a nullable `source` column instead.
- `_write`: when `words.isEmpty` and the note is from the watch, it sets `wordsPending: false` and a `noWords` mark, keeps the recording, does not send, and shows no *Nothing was saved* notice.
- The timeline's subtitle for such a note is *No words heard*; its title is already *Voice note* for an empty voice note. **Try again** is not offered: the model gave its answer.
- A no-words watch note is not queued to send. If the person types words into it, it sends as any edited note does.

### How long it takes

With the iPhone near and on, a note reaches the phone in a few seconds, and the watch shows *On your iPhone*. It shows in the phone app at once when the app is open, else at the next open. With the iPhone away, it waits on the watch.

## Risks / Trade-offs

- **The real cause is unproved.** If the recordings are silent, this change shows that (a *No words heard* note you can play) but does not fix the microphone. The follow-up is then a recording fix, such as `.playAndRecord` or a different sample rate, decided by what the played note sounds like.
- **Leaving saves.** A recording you meant to drop is kept if you press the Crown; the *X* drops it. Under 1 s keeps nothing.
- **`sendMessage` wakes only from a foreground watch app.** A note saved by leaving the app may not wake the phone; it then goes when the system sends it, usually within minutes.
- **No real watch here.** CI compiles and runs `RelayWatchTests` on a simulator. The real check is the person's watch with the next TestFlight build.

## UX

### Use-case brief
Who: Matthew. Job: keep a thought in seconds without the phone. Done: the note is on the phone, with words. Common: raise wrist, open app, talk, tap or drop the wrist and press the Crown. Edge: iPhone away, no words, microphone refused, accidental open (under 1 s keeps nothing). Frequency assumed: a few notes a day.

### Flow
Open (app list, watch face button, Action button) → recording → tap → *Saved* / *Sending to your iPhone* → *On your iPhone*. Or open → recording → Crown → saved in the background. Tap on *Saved* → a new recording. *X* → nothing kept, *Saved* is not shown; the screen shows *Tap to record*.

### Hierarchy
- Recording: the whole screen is the save target; the time on top, the *X* small at the top right, the bars in the middle, *Tap to save* small and grey.
- Saved: the amber check and *Saved*; the iPhone state small under it; *Tap for a new note* smallest.

### Review
[review.html](review.html). The first What Changes item sketches the two screens; the third the phone row.

### Components
SwiftUI with `WatchBrand` colors and Inter, as today. The phone row reuses the timeline's voice row and its subtitle.
