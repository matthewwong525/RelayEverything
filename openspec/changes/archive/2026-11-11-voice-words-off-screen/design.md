# Design

## Context

See proposal.md, Why. What the code shows:

- `WhisperTranscriber` loads one `WhisperEngine` at the first recording and keeps it (`_engine ??=`). On a real iPhone `whisperConfig()` gives `WhisperBackend.automatic`, which the package's `wf_context_create` turns into `use_gpu = true` (Metal). Only the simulator gets `WhisperBackend.cpu`.
- iOS refuses Metal command buffers from an app that is not in the foreground. In the package's `ggml-metal-context.m`, a command buffer that does not complete sets `ctx->has_error = true`, and `ggml_metal_graph_compute` then returns `GGML_STATUS_FAILED` "until the backend is recreated". `whisper_full` fails, the bridge sets `whisper_full failed with code <n>`, and Dart gets a `WhisperException`.
- Since #110 and #115 a watch note wakes the iPhone app in the background. `RelayWatchReceiver` calls `ShortcutsEngine.shared.inboxChanged()`, the app's own engine drains the inbox, and `keepRecording` starts `_write` at once. That is the first write the app makes off screen.
- `_write` catches every error, adds the note to `_wordsFailed` (memory only) and prints the error with `debugPrint`. A TestFlight build keeps no log, so the reason is lost.
- `resume()` drains the inboxes and pulls notes. It does not write failed notes again; only `load()` (through `_writePending`) and **Try again** do.
- `Entry.failed` carries no reason.

## Goals / Non-Goals

**Goals:**

- A write off screen works on an iPhone.
- An engine that failed is never used again.
- A failed note recovers with no tap, and its reason is on the phone.

**Non-Goals:**

- No Core ML encoder, no second engine, no change to `TranscribeOptions`.
- No store column for the reason: it lives as long as the failed mark does, in memory.
- No change to how Android loads the engine.

## Decisions

### The iPhone engine runs on the CPU

`whisperConfig()` returns `WhisperConfig(backend: WhisperBackend.cpu)` when `Platform.isIOS` (the simulator rule folds into it), else the default. It keeps its optional argument for tests, as a platform flag in place of the executable path.

- Over *GPU on screen, CPU off screen*: that needs the app's lifecycle state in the transcriber, an engine swap on each change, and still fails for a job that is running when the app leaves the screen. The model is `ggml-base.en-q5_1` (57 MB): the CPU cost for a short note is small.
- Over *retry on the CPU after a GPU failure*: the same swap, and each off-screen note pays one failed run first.

### A failed run drops the engine

In `WhisperTranscriber.write`, a run that throws, other than the app's own cancel at the time limit, disposes the engine and sets `_engine = null` before the error goes on. The next `write` loads a new engine. `dispose` throws while a job is active, so the drop runs after `task.result` completes, in a `try`/`catch` that ignores a dispose error and still clears the field. A cancelled run keeps the engine: the cancel is the app's, not the engine's fault.

This rule is not for Metal alone. Any native error state then costs one note, not every note until the app closes.

### The reason is kept beside the failed mark

`_wordsFailed` becomes a map from note id to a reason. `_write` makes the reason from the error:

- `TimeoutException` → `the phone took more than <limit>.`, with the limit in minutes.
- `WhisperException` with `whisper_full failed with code <n>` → `the speech engine stopped (code <n>).`
- any other error → `the speech engine stopped (<first 80 characters of the error, one line>).`

`Entry` gets `String? why`. The note page shows `Why: <reason>` in the page's small muted style, between the failed line and **Try again**, only when `why` is not null. The list row does not change.

### Return to the app writes failed notes again

`resume()` calls the same code as `writeWordsAgain()` after it drains the inboxes. `writeWordsAgain` already clears the failed marks first and writes only those notes, so a note that is being written now is not written twice. The one-time notice stays as it is: it shows again only if a note fails again.

### Swift holds a background task for a watch note

`RelayWatchReceiver.session(_:didReceive:)` begins a `UIApplication` background task (`relay.watch-note`) before it calls `inboxChanged`. `ShortcutsEngine.inboxChanged` takes a completion and passes it as the result callback of `invokeMethod("inboxChanged")`; with no app engine, or while the engine is not ready, it completes at once (the pending flag still makes the app drain later). The task ends at the completion or in its expiry handler, each at most once.

In `bridge.dart`, the `inboxChanged` handler awaits `drainShortcutsInbox()` and then the writes it started. `RelayController` gets a public `Future<void> wordsSettled()` that does what `wordsWritten()` does today (`wordsWritten` stays as the test name and calls it). `_write` already awaits `sync()` after it sets the words, so the task covers the send too.

Swift is first compiled on GitHub's Mac, as [open source](../../../wiki/open-source.md) says.

## UX

This change adds one line to one state of an existing screen; it restructures nothing. The brief: the person opens a voice note that shows *The words did not come* and wants to know if the recording is safe and what to do. The primary action stays **Try again**. The *Why* line is secondary text: small, muted, one line, no action. It mirrors the *No words, only the recording.* style of the same page.

### Review

[review.html](review.html) shows the page before and after in the What Changes item *A failed note says why*.

## Risks / Trade-offs

- [The cause is inferred, not seen on the phone] → The engine drop and the try on return recover from any engine failure, not only this one, and the *Why* line gives the next failure's reason.
- [CPU is slower for a long note] → The time limit is 2 minutes or the note's length, and a 5-minute note has 5 minutes. If a real note comes near the limit, revisit with a measurement from the phone.
- [iOS gives less than the time the write needs] → The pending note is written at the next run of the app, and the failed mark, if the time limit passed while the app was stopped, clears on return.
- [The Swift change can't be compiled or run here] → CI compiles it; the watch hand-off is checked on the real watch, as the proposal's *What the build needs* says.
