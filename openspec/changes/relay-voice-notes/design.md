# Design

## Context

This change builds on `relay-offline-by-default` (workspace *SHIP: Relay offline notes by default*, branch `elderly-husky`), which must be on `main` first. After it, `mobile/` has:

- `lib/data/settings.dart` (`sending`, `pinNotes`, `health`, `history`) and `lib/data/sender.dart`, the one gate in front of the HTTP client, which returns nothing while `sending` is off.
- `lib/data/store.dart`: a local `notes` table (`clientId`, `text`, `createdAt`, pin, `sentAt`) that the timeline reads, and `outbox(id, destination, kind, payload, createdAt)`.
- A test that gives the app an HTTP client which fails on any call and drives every screen with sending off.

Pebble ring notes reach the server from Pebble's app with Pebble's own words (`app/worker/apps/relay/pebble.ts`); the phone never holds their sound. The server's note route takes text, a time and a pin, and `timeline.ts` knows the sources `ring` and `typed`. The phone app targets iOS 15 and Android API 26.

## Goals / Non-Goals

**Goals:** voice notes that work offline end to end; one engine (`lib/voice/`) the Relay ring's Bluetooth path can call later with a recording file; no new server surface.

**Non-Goals:** streaming words while the person talks; a cloud fallback; other languages; a server `voice` source; editing words.

## Decisions

### whisper.cpp through a Flutter binding, run in a background isolate

- First choice: `whisper_cpp_flutter_plus` (whisper.cpp 1.9.x, iOS 14+, Android API 24+, Metal and Accelerate on iOS, file transcription and voice-activity detection). Task 1.1 checks it builds in our CI and runs `ggml-base.en-q5_1` on a 10 s sample. If it fails, fall back to `whisper_ggml_plus`, then to a small FFI plugin over whisper.cpp copied into `vendor/` with its MIT license. `whisper_edge` is out: it needs iOS 16.4.
- Hidden behind `abstract class Transcriber { Future<String> words(File wav); }`, so tests use a fake and the ring can reuse it.
- Run in a background isolate: `base.en` on a recent iPhone writes 10 s of speech in about 1 to 2 s; a busy UI thread would freeze the timeline.
- Alternative: the phones' own speech services (Apple `SFSpeechRecognizer`, Android `SpeechRecognizer`). Rejected: Android's service may send audio to Google, and the two give different results, so the promise *your voice never leaves the phone* would depend on the phone.

### The model: `ggml-base.en-q5_1`, fetched on the first voice note

- Downloaded from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q5_1.bin` to the app's support folder (not backed up to iCloud: `NSURLIsExcludedFromBackupKey`), via a `.part` file that resumes with an HTTP `Range` and is renamed only after its SHA-256 matches the constant in `lib/voice/model.dart`.
- The download uses its own small HTTP client in `lib/voice/model.dart`, not `Sender`: it is the one request allowed with sending off, and it never carries the device key. The offline change's fail-on-any-call test changes to allow exactly this URL, and only after the person's *Get it*.
- States: `missing → asking → downloading(progress) → ready`, plus `failed` (retry). `Remove` in Settings deletes the file and returns to `missing`.
- Alternatives: bundle the model in the app (every install 57 MB larger, used or not); download at first open (breaks the offline promise); serve it from relayeverything.com (Workers static files stop at 25 MiB) or the Relay server (the phone may have none).

### Recording: hold to talk, 16 kHz mono WAV, kept on the phone

- `record` package, `AudioEncoder.wav`, 16 kHz, mono: the format whisper.cpp reads, so no conversion step. About 2 MB a minute. Files live in `<support>/voice/<clientId>.wav`, out of phone backups: `voice/` in Android's backup rules, and each kept file marked through the `relay/files` channel on iOS.
- Hold starts recording on `onLongPressStart`-like pointer down; release saves; a drag outside the button cancels. A hold under 500 ms is dropped and its file deleted. A cap of 5 minutes ends the note by itself, so a stuck press can't fill the phone.
- Microphone permission is asked on the first hold after the model is ready: `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist`, `RECORD_AUDIO` in the Android manifest. A refused permission shows a line pointing to the phone's settings.
- Playback with `just_audio` from the local file.

### Notes: one table, a `kind` and a words state

- Add to the `notes` table: `kind` (`typed` | `voice`), `audioPath` (nullable), `durationMs`, and `wordsPending` (bool). A drift schema step adds the columns with defaults (`typed`, null, null, false).
- Save flow: insert the row with `wordsPending = true` and empty text → transcribe → if the cleaned words are empty, delete the row and the file and show *No speech heard* → else set `text`, `wordsPending = false`, and enqueue the outbox row if `sending` is on.
- Cleaning drops whisper.cpp's non-speech marks (`[BLANK_AUDIO]`, `(music)`, `[ Silence ]`, and any text wholly in `[]` or `()`), then trims. The voice-activity check, where the binding has one, runs first and skips the model on silence.
- On app start, rows with `wordsPending = true` and a file are transcribed again; rows with no file are deleted.
- The outbox payload is the typed-note payload (`clientId`, `text`, `createdAt`, pin). No server change: the server shows it as *Typed*; the phone shows *Voice* from `kind`.
- *Send them* (offline change's earlier-notes prompt) skips rows with `wordsPending`; they enqueue when their words land.

### Site and docs

- New `site/src/content/docs/app/voice-notes.md`, listed in `site/sidebar.mjs` after `app/your-notes`.
- `app/your-notes.md`: the *Voice* mark and the play button. `app/settings.md`: the *Voice notes* section. `privacy.md`: a row for voice recordings (*this phone only, never sent*) and the model download from Hugging Face (it sees the phone's address, nothing else).
- `mobile/README.md`: *What it does* gains *Voice notes*.
- `ring/how-it-works.md` keeps its *No speech, no note* rule; it now names the same check the app runs.

## UX

### Use-case brief

Matthew, and anyone with the public app, wants a thought kept in seconds while walking or driving, without typing. Done is the note's words in the timeline. Context: one hand, phone out for a moment, often no signal. Common case: a 5 to 30 s note, several times a day. Rare: the first model download (once) and removing the model (almost never). Mirrors the offline change's timeline and Settings screens.

### Flow

Open → hold *Hold to talk* → speak → let go → note shows → words fill in. First time only: tap → *Get the speech model?* → *Get it* → progress card on the timeline → microphone permission on the first hold. Edge: under 0.5 s or no words → nothing saved, a short *No speech heard*; slide off → cancelled.

### Hierarchy

Timeline: *New note* stays the primary action; *Hold to talk* is the ghost button beside it, larger tap target (at least 56 px), so a thumb finds it. While held, a listening card with a timer replaces nothing and pushes nothing. Model dialog: *Get it* is primary, *Not now* ghost. Settings: no primary action; *Remove* is a ghost button.

### Review

[review.html](review.html): What Changes items 1 (timeline with voice notes), 2 (while holding), 3 (model dialog and progress), 6 (Settings).

### Components

Material 3 `Card`, `Chip`, `FilledButton`, `OutlinedButton`, `AlertDialog`, `LinearProgressIndicator` and `SnackBar` as in the offline change. One new widget, `HoldToTalkButton`: a `Listener` over an `OutlinedButton` for press, release and slide-off, because Material buttons give no release-outside event.

## Risks / Trade-offs

- **[Native build in CI]** whisper.cpp compiles with the NDK on each Android build, adding minutes. → Cache Gradle and the NDK in `mobile-android.yml`; task 1.1 measures it.
- **[A binding stops being kept up]** → `Transcriber` hides it; the `vendor/` FFI plugin is the fallback.
- **[57 MB on mobile data]** → The dialog says the size; the download resumes after a drop.
- **[Older phones are slow]** → Words run in the background; the note shows at once with *Writing the words…*.
- **[Hugging Face moves or drops the file]** → The checksum refuses anything else; a failed download says so and offers *Try again*. Moving the URL is a one-line change.
- **[The `relay-sending` delta targets a spec that is not on `main` yet]** → The build starts only after `relay-offline-by-default` publishes; task 5.1 checks the requirement text still matches.

## Migration Plan

Notes saved before this change get `kind = typed` from the schema step. Removing the change leaves voice rows readable as typed notes with words; their recordings stay in the app's folder until the app is removed.
