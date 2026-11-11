# How the Apple Watch app hands notes to the phone

The Relay Everything watch app records a voice note and hands it to the paired iPhone, which keeps it and writes its words. This page gives the rules that are not clear from the code. Up: [the wiki](README.md).

## The parts

- **The watch app** is native Swift in [`mobile/ios/RelayWatch/`](../mobile/ios/RelayWatch/): Flutter can't build for watchOS. The Linux build computer has no Xcode, so the first compile is GitHub's Mac, as [open source](open-source.md) says.
- **The iPhone side** is [`RelayWatchReceiver.swift`](../mobile/ios/Runner/RelayWatchReceiver.swift). It moves each file into the shortcuts inbox, and Dart keeps it from there, as a note from Shortcuts.
- **The watch deletes its copy only on `kept`** from the iPhone. If no note waits on the watch, the phone got it: look for the loss on the phone, not in the hand-off.

## What WatchConnectivity does and doesn't do

- **`transferFile` queues, but does not hurry.** The system sends when it chooses, and it does not reliably wake the iPhone app. A note sent this way can wait until the next time the phone app opens.
- **`sendMessage` from a watch app on screen wakes the iPhone app** in the background, when `isReachable`. The watch sends a small wake message beside each file, so the queued file arrives in seconds. Never put the recording in a message: messages are small, and the file transfer keeps the queue's promise.
- **A watch app can't close itself.** The person leaves with the Digital Crown, or the clock comes back after the wrist goes down. Put work that must happen on leave in the `scenePhase` change to `.background`. `.inactive` is only a wrist down.

## The phone keeps every watch note

A voice note held on the phone with no words is deleted, because it was a mistaken hold. A watch note with no words is kept as *No words heard*, with its recording, and is not sent. The person can't hear the recording on the watch, so a deleted watch note is a silent loss. The note keeps its `source` (`watch`) in the store, not in its body, because the body is what gets sent.

## Testing it

CI builds the signed app with the watch app and runs `RelayWatchTests` on a watch simulator. No check here can make a watch hand a file to a phone: the real test is the person's own watch with a TestFlight build. Keep the screen and queue rules in plain Swift types with no hardware, so `RelayWatchTests` can test them.

## See also

- [How the phone sends health, places and the calendar](relay-phone-sync.md): the phone's own background round.
- [The device check](development/device-check.md): what the iPhone simulator check can show.
