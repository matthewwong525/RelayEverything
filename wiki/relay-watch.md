# How the Apple Watch app hands notes to the phone

The Relay Everything watch app records a voice note and hands it to the paired iPhone, which keeps it and writes its words, often off screen. This page gives the rules that are not clear from the code. Up: [the wiki](README.md).

## The parts

- **The watch app** is native Swift in [`mobile/ios/RelayWatch/`](../mobile/ios/RelayWatch/): Flutter can't build for watchOS. The Linux build computer has no Xcode, so the first compile is GitHub's Mac, as [open source](open-source.md) says.
- **The iPhone side** is [`RelayWatchReceiver.swift`](../mobile/ios/Runner/RelayWatchReceiver.swift). It moves each file into the shortcuts inbox, and Dart keeps it from there, as a note from Shortcuts.
- **The watch deletes its copy only on `kept`** from the iPhone. If no note waits on the watch, the phone got it: look for the loss on the phone, not in the hand-off.

## What WatchConnectivity does and doesn't do

- **`transferFile` queues, but does not hurry.** The system sends when it chooses, and it does not reliably wake the iPhone app. A note sent this way can wait until the next time the phone app opens.
- **`sendMessage` from a watch app on screen wakes the iPhone app** in the background, when `isReachable`. Never put the recording in a message: messages are small, and the file transfer keeps the queue's promise.
- **`isReachable` on a watch is true only while the watch app is on screen.** A save on leave runs at `.background`, when the app is off screen, so a wake sent then can fail. The watch sends a small wake at three moments: when a recording starts, at `.inactive` while it records (the start of a leave, or a wrist down), and beside each file at the save. Then the iPhone app is awake when the file comes, and the file arrives in seconds. A wake that fails costs nothing: the file waits in the queue.
- **A watch app can't close itself.** The person leaves with the Digital Crown, or the clock comes back after the wrist goes down. Put work that must happen on leave in the `scenePhase` change to `.background`. `.inactive` comes before a leave, but also with a wrist down, so it may only wake the iPhone.

## Numbers on an older watch are 32 bits

Swift's `Int` is the size of a pointer. A Series 4 to 8, an SE, an SE 2, the first Ultra, and every watch on watchOS 10 or 11 run the `arm64_32` slice, where `Int` is 32 bits: its largest value is 2,147,483,647. A time in milliseconds since 1970 is about 1.8 trillion, so `Int(...)` of it stops the app. That stop at save closed the app on a Series 8, and no note waited.

- **Write a time, or any number that can pass 2 billion, as `Int64`**, not `Int`. `WatchNote.createdAt` is an `Int64`; the iPhone reads it as an `NSNumber`, which holds it.
- **The watch simulator never shows it.** Every watch simulator is 64-bit, so `RelayWatchTests` pass on code that stops a Series 8.
- **The build compiles for `arm64_32` but can't run it.** [`watch-tests.sh`](../mobile/device-check/watch-tests.sh) first compiles the watch app and its tests for `arm64_32`, so a literal too large for a 32-bit `Int` fails the build. A number that grows too large while the app runs passes that compile: the real proof is an older watch with a TestFlight build.

## The phone keeps every watch note

A voice note held on the phone with no words is deleted, because it was a mistaken hold. A watch note with no words is kept as *No words heard*, with its recording, and is not sent. The person can't hear the recording on the watch, so a deleted watch note is a silent loss. The note keeps its `source` (`watch`) in the store, not in its body, because the body is what gets sent.

## The phone writes the words off screen

A watch note starts the iPhone app in the background, so the iPhone writes its words with the app off screen, often with the phone locked. Three rules keep that working:

- **An iPhone refuses GPU (Metal) work from an app that is not on screen.** whisper.cpp on the GPU then fails the run at once. So on an iPhone the speech engine always runs on the processor: `whisperConfig` in [`transcriber.dart`](../mobile/lib/voice/transcriber.dart). One way for both cases has no switch to get wrong, and a note half written when the person locks the phone also finishes. The cost is about one or two seconds on a short note with the 57 MB base model.
- **A speech engine that failed once must be made again.** After one failed Metal run, ggml keeps an error state and fails each later run until the engine is made again. So a failed run disposes the engine, and the next note loads a new one; a run the app cancelled at its time limit keeps it. Without this, one failure becomes every note until the app closes. A return to the app also writes failed notes again, and the note's page shows the reason on a *Why* line, because a TestFlight build keeps no log.
- **The app asks iOS for time at the hand-off.** `RelayWatchReceiver` begins a background task (`relay.watch-note`) before it tells Dart, and ends it when Dart's `inboxChanged` answers, after the words are written and sent, or when iOS takes the time back, about 30 seconds. Each path ends the task once. A note iOS stops first gets its words the next time the app runs.

## Testing it

CI builds the signed app with the watch app, compiles the watch app for the [32-bit watch](#numbers-on-an-older-watch-are-32-bits), and runs `RelayWatchTests` on a watch simulator. No check here can make a watch hand a file to a phone: the real test is the person's own watch with a TestFlight build. Keep the screen and queue rules in plain Swift types with no hardware, so `RelayWatchTests` can test them.

## See also

- [How the phone sends health, places and the calendar](relay-phone-sync.md): the phone's own background round.
- [The device check](development/device-check.md): what the iPhone simulator check can show.
