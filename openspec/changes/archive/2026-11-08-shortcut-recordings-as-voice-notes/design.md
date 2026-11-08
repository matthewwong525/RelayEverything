# Design

## Context

*Add a note* (`AddNoteIntent` in `mobile/ios/Runner/RelayIntents.swift`) copies each `IntentFile` into `shortcuts-inbox/<id>/` and calls Dart's `add` on the `relay/shortcuts` channel, on the app's engine when it is ready, else on a headless engine (`shortcutsMain`), else it leaves `shortcuts-inbox/<id>.json` for the next open. `ShortcutsBridge.add` calls `RelayController.keepNote`, which keeps every file as an attachment.

A held voice note goes through `_keepVoice`: a `LocalNote` of kind `voice` with `audioPath: voice/<clientId>.wav`, `durationMs` and `wordsPending: true`, stored by `store.addVoiceNote`; `_write` runs whisper.cpp on the 16 kHz mono WAV and calls `store.setWords`, which replaces the text and queues the note when sending is on. `load` writes every pending note's words (`_writePending(dropStray: true)`) after it drains the inbox. The headless engine has no `voice` parts, so it cannot write words.

Shortcuts' *Record audio* gives an `.m4a` (AAC).

## Goals / Non-Goals

**Goals:** a lone recording from Shortcuts becomes a pending voice note on every path (app engine, headless engine, inbox), and its words are written by the same `_write` as a held note.

**Non-Goals:** writing words in the headless engine; a recording plus other files as a voice note; any server or webhook change (a voice note already reaches them as words).

## Decisions

- **Swift converts the audio, not Dart.** In `AddNoteIntent`, when `files` holds exactly one file whose `UTType` conforms to `.audio` (or `.audiovisual` with an audio track is out of scope), read it with `AVAudioFile` and write `shortcuts-inbox/<id>/voice.wav` as 16 kHz mono 16-bit PCM through `AVAudioConverter`. Apple's tools read every format Shortcuts makes; Dart has no decoder for AAC. The request then carries `recording: {path: "shortcuts-inbox/<id>/voice.wav", durationMs}` and an empty `files` list. A conversion failure, or a source over 25 MB, falls back to today's plain-file path (the 25 MB message stays as is).
- **One Dart entry for a shortcut recording.** Add `RelayController.keepRecording(String text, {required String recording, required int durationMs, String? clientId, DateTime? createdAt, bool pin = true})`: it stores a voice note like `_keepVoice` does, then moves the WAV to `voice/<id>.wav`, with `text` holding the typed words (trimmed), pinned as `keepNote` pins a note, and writes its words at once when `voice` parts exist (`_track(_write(note))`); without them the note waits for the next `load`. A `clientId` already kept is not kept twice, as in `keepNote`. `ShortcutsBridge.add` and the inbox drain in `load` both call it when the request has `recording`. `InboxRequest` gains `recording` (path and length).
- **Typed words first.** `store.setWords` joins the note's existing text and the written words with a newline when the text is not empty. In `_write`, empty written words with typed words keep the note: `setWords(clientId, '', …)` gives it its typed words only and clears `wordsPending`; the recording stays. Without typed words, today's drop and *No speech heard* notice stay.
- **The parameter summary** becomes `Summary("Add \(\.$text) with \(\.$files) to Relay Everything")`, so the slot shows in the line.
- **The returned note** (`noteMap`) is the pending voice note: `kind: voice`, the typed words, no files. Shortcuts shows the words when the note has some.

## Risks / Trade-offs

- [A very long recording] → whisper's time limit already grows with the length, and *Try again* covers a failure; the 25 MB source limit caps the length.
- [The headless engine runs out of time before Dart answers] → the inbox path carries `recording`, and `load` drains the inbox before `_writePending(dropStray: true)`.
- [A shortcut runs while the app opens] → the WAV reaches `voice/` only after its note is kept, and the stray sweep checks the store again before it deletes a file, so the WAV is never seen as stray.
- [Conversion takes time inside the 20-second budget] → AVAudioConverter on a few minutes of audio takes well under a second on a phone; it runs before the engine call.

## Migration Plan

None: no stored data changes shape. A build without this change keeps a recording as a file, as today.
