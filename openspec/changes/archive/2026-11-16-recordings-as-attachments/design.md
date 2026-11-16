# Design: recordings as attachments

## Context

Today a voice note is a `LocalNote` with `kind: NoteKind.voice`, one `audioPath` (`voice/<clientId>.wav`, 16 kHz mono WAV, at most 5 minutes), `durationMs`, and `wordsPending`. The written words are the note's `text`. The server never learns that a note was spoken: the phone sends it as a typed note with the words as `text`, and the recording never leaves the phone. Files are `Attachment`s (`attachments/<id><.ext>`), listed on the note's upload by id, name, type and size, with the bytes sent after by `POST attachments` and sealed in the space. The server's one `FILES` subquery in `app/worker/apps/relay/queries.ts` gives the files to the page, the phone sync, the web API and the AI connector. Webhooks list files in `attachments` and send the bytes as `note.file`.

## Goals / Non-Goals

**Goals:** a recording is one of a note's files, with its own transcript and length; the note's text is only typed words; several recordings per note; a mic in the note's bars; the sound goes to the space like any file; old voice notes move once.

**Non-goals:** removing one file or recording from a note; recording on the web or Mac; a recording placed between lines; a smaller audio format.

## Decisions

### A recording is an `Attachment` with `lengthMs` and a transcript

`Attachment` (phone store) gets `lengthMs` (int?, set only for a recording), `transcript` (String?), `wordsPending` (bool) and `wordsFailed` handling moves from the note to the attachment (keyed by attachment id in the controller's failed map). A recording is an attachment with `lengthMs != null`. It also gets `top` (bool): true only for the recording a held *New note*, Shortcuts or the watch starts a note with. A `top` recording shows above the words; every other recording shows after the words with the pictures and files, in list order, as an added photo does. A picked `.m4a` from *Attach* stays a plain file: only the app's own recorder, Shortcuts' single recording and the watch make recordings. The recording file moves from `voice/<clientId>.wav` to `attachments/<id>.wav`, so the existing file upload, sweep and download paths carry it. The writing queue (`voice/transcriber.dart` and the controller's job list) is keyed by attachment id, not note id, so two recordings in one note write in turn.

`NoteKind.voice` stays as the note's kind for a note made by a held *New note*, Shortcuts or the watch, so *No speech, no note* still drops an empty new voice note; filters and row icons read "has a recording" instead of the kind.

`Entry` gets `recordings: List<EntryRecording>` (attachment id, path or URL, length, transcript, writing, failed, why, noWords); `Entry.files` keeps only non-recordings. `Entry.voice`, `recording` and `length` go; their readers move to `recordings`.

### The note waits for its new recording's words, then sends once

A note with a recording whose `wordsPending` is true gets no upload, as today. When the words are written or fail, the note's upload (or, for a sent note, its `PATCH notes`) lists the recording with `transcript` and `lengthMs`, then the bytes follow through the file upload. A failed recording goes with `transcript: null`; a later *Try again* sends a `PATCH` with the new transcript. A transcript edit is a note edit: it sets the note's `editedAt` and sends the full file list with transcripts.

### Server: two columns and a transcript change

New space migration `0021_recording_transcripts.sql` (`0020` is *Delete like Apple Notes*'s; a space records each step by name, so either may run first): `ALTER TABLE relay_attachments ADD COLUMN transcript TEXT` and `ADD COLUMN length_ms INTEGER`, `ADD COLUMN top INTEGER NOT NULL DEFAULT 0`, and a trigger that moves the note's `relay_note_changes` row when either changes, as `0011` does for a listed file. `TypedNote.attachments` and `PATCH notes` `attachments` take optional `transcript` (≤ 100 000 chars), `lengthMs` and `top`. `PATCH notes` updates a known file's `transcript` when it differs, under the same `edited_at` rule, and logs one `note.updated`. `FILES` adds `transcript`, `lengthMs` and `top`; `GET notes` and the connector's note shape carry them. The `words` filter in `queries.ts` also matches `relay_attachments.transcript` through `EXISTS`. `GET attachment` keeps refusing nothing new; the AI connector and the web API keep returning no bytes for any file, so no sound reaches an AI app.

### Webhooks

`format.ts`'s `attachment` gets optional `transcript` (string or null) and `length_ms`. `note.updated` already carries `attachments`. `note.file` sends a recording's bytes like any file. The phone's own webhook mode (`mobile/lib/data/webhook.dart`) lists the same fields, and `mobile/test/webhook_test.dart` writes the fixtures `format.test.ts` and the example receiver read. `site/public/webhooks/v1.schema.json` is rebuilt with `npm run relay:api-doc`. Both webhook paths carry the same fields: the server's send for a signed-in phone, and the phone's send for a person with no account. If the *Simplify Relay Everything webhooks* change lands first, a signed-in phone has no webhook of its own, so only those two paths change. Version 1 may change before the public release, and the website says so: a voice note's words leaving `text` is that kind of change.

### The move of old voice notes

A one-time store step (a new store version) turns each `kind == voice` note with `audioPath` into: one `Attachment` (`id` new, name `Recording.wav`, type `audio/wav`, size from the file, `path` the moved file, `lengthMs` = `durationMs`, `top` = true, `transcript` = the note's plain words or null while pending, `wordsPending` copied), and the note's `text` set to empty. A note whose file is gone keeps its words as text and gets no attachment. For a note already sent, the step queues one `PATCH notes` with `text: ''` and the file list, then the file upload, only while sending is on; with sending off, nothing queues, and the note goes when sending turns on, as earlier notes do with *Send them*. A watch note with no words, never sent before, sends now as a note with one recording and no transcript.

### Web page and Mac

Both draw `RecordingCard` from the same `note_blocks.dart`. With no local file, play streams `GET attachment` (the web page already plays from a URL; the Mac downloads to its notes folder first). A recording whose bytes have not arrived shows its transcript and *Still on your phone*. Neither shows *Record*.

## UX

### Use-case brief

Matthew records a thought while walking, then later opens it at a desk to add a to-do list or a second thought. The job: keep what he said and what he wrote side by side, without the two mixing, and read the said part only when he needs it. Phone first; the web page and Mac read and play. Recording happens a few times a day; reading a full transcript is rarer than glancing at its first lines.

### Flow

Hold *New note* → talk → tap → the note opens with one card, *Writing the words…*, then 2 lines of transcript, and *Add notes…* under it → type. Later: open the note → tap the mic → talk → tap → a second card shows at the bottom, after the words, as an added photo would. Tap *Transcript* to read all of it or fix a word.

### Hierarchy

The note's own words are the main content and keep the note's large first-line style; the cards above are quieter: white cards, muted *Transcript* label, 15 pt transcript text. *New note* (compose) stays the one filled button; the mic is a plain icon in the frosted pill, as *Attach* is.

### Review

[review.html](review.html): What Changes items 1 to 3 carry the pictures.

### Components

Reused: `VoicePlayer` (inside the card, without its own `Card`), `_FrostedPill`, `PillIconButton`, `AttachButton`'s rule for which notes may add files, the full-screen recording screen from `hold_to_talk.dart`, the note editor's placeholder. New: `RecordingCard` in `note_blocks.dart` (the player, a hairline, and the folding transcript with a copy button and an editable text field when open), because no part shows a player with text under it.

## Risks / Trade-offs

- **Privacy promise.** The website says today that a voice note's recording never leaves the phone. This change ends that. The privacy page, the voice notes page and the store listing text must change in the same publish.
- **Upload size.** At about 2 MB a minute, a 5-minute recording is about 10 MB. It goes over mobile data like a video would; the existing file upload already handles retries.
- **Webhook receivers** that read a voice note's words from `text` get an empty text. Only Matthew's own receivers exist before the public release.
- **App Store privacy answers.** The app now sends recordings, which Apple counts as *Audio Data*. `app_privacy_details.json` (on main since PR #136) and the answers set by hand in App Store Connect do not name it; Apple can refuse an app whose answers miss data it sends. The build adds `AUDIO_DATA` (`APP_FUNCTIONALITY`, `DATA_LINKED_TO_YOU`, no tracking) to the file, and the person adds it in App Store Connect before the next release.
- **The note's bottom bar.** The *Apple-style note toolbar* chat plans a new bar and editor for the note page, with the mic after *Attach*. Whichever change publishes second puts the other's buttons in its own bar: this change's *Record*, or that change's new layout.
- **One path per webhook.** The *Simplify Relay Everything webhooks* chat plans to send a signed-in phone's webhooks only through the server, and a phone with no account only to its own webhook. Whichever change publishes second puts the other's shape in its code: this change's recording fields on both paths, or that change's single path.
- **No toasts.** *Delete like Apple Notes* removes every toast on the phone, the web page and the Mac, and shows problems as an Apple-style alert; a deleted note opens read-only. This change adds no toast of its own but the transcript's *Copied* message: whichever lands second drops it and sends recording problems through that change's alert.
- **Recently Deleted.** The *Delete like Apple Notes* change is being built now and changes how the server keeps notes. The build starts from the newest main after it lands.
- **Two changes add a migration.** *Delete like Apple Notes* edits the same files; the one that publishes second takes the next number and rebases.

## Testing

- Phone: store step on a voice note (sent, unsent, pending, failed, missing file, watch with no words) and its single run; keeping and sending a note with two recordings; transcript edit sends a `PATCH`; row title and search read transcripts; `RecordingCard` folds and opens; *Record* hidden on web, Mac and for a note from elsewhere; 10-file refusal; Shortcuts given words become text.
- Server: migration on old rows; `POST notes` and `PATCH notes` with transcripts (newer wins, same transcript logs nothing); `GET notes` and connector shapes; search by transcript; webhook format and fixtures.
- Device check: a Maestro flow that opens a seeded voice note, opens the transcript and types a note under it (no microphone sound in the simulator).

## Decision log

- **2026-11-15** — Asked: should the transcript be part of the note, or apart from it → chose apart: a recording card with the transcript folded under it, and the person's own notes under the card.
- **2026-11-15** — Asked: what a voice note's text holds for the server, AI and webhooks → the person said a recording should be like an attachment, so the text holds only typed words and each recording carries its own transcript.
- **2026-11-16** — Asked: should the recording's sound upload → chose yes, like any attachment, with the transcript as an extra.
- **2026-11-16** — Asked: add a mic in the note's bars in this change → chose yes.
- **2026-11-16** — Asked: another chat (*Delete like Apple Notes*) edits the same server note files → chose to keep going here.
- **2026-11-16** — Assumed: the transcript starts folded to 2 lines on every note, because the person asked for "a dropdown to see the transcript".
- **2026-11-16** — Asked: where a recording added with the mic goes → chose the bottom, after the words, with the photos and files in the order added, as adding a photo works; only the recording a voice note starts with stays at the top. This replaces the earlier assumption that all recordings sit at the top.
- **2026-11-16** — Assumed: a transcript can be corrected in place, because the person picked the first answer, which offered it.
- **2026-11-16** — Assumed: recordings of earlier voice notes also go to the space while sending is on, because one shape for all recordings keeps the build simple and only the person's own phone holds old ones before the public release.
- **2026-11-16** — Assumed: a watch recording with no words now goes to the space with no transcript, because the sound itself is the content once recordings are files.
- **2026-11-16** — Assumed: a recording with no words, made with the mic in a note, stays in the note, because a tap on the mic is deliberate, unlike a bump on *New note*.
- **2026-11-16** — Assumed: AI apps and the web API get transcripts but never the sound, because their specs promise no recording is returned.
- **2026-11-16** — Assumed: an audio file picked with *Attach* stays a plain file with no transcript, because only the app's own recordings get words written.
- **2026-11-16** — Assumed: deleting one recording waits for a later change, because no file can be taken out of a note today.
- **2026-11-16** — Assumed: the recording stays WAV, because a 5-minute recording is about 10 MB, under the 25 MB file limit.
- **2026-11-16** — Assumed: add `AUDIO_DATA` to the App Store privacy answers file and a step for the person in App Store Connect, because the daily's line-up note found the answers miss the recordings this change sends.
- **2026-11-16** — Assumed: whichever of this change and the *Apple-style note toolbar* change publishes second takes the other's bar edits, because the daily's line-up note found both change the note's bottom bar.
- **2026-11-16** — Assumed: the build starts from the newest main after *Delete like Apple Notes* lands, because the daily's line-up note said that change reshapes how the server keeps notes.
- **2026-11-16** — Assumed: the recording's fields go on both webhook paths the *Simplify Relay Everything webhooks* change keeps (server send when signed in, phone send with no account), and whichever change publishes second follows the other, because the daily's line-up note found both change how webhooks send.
- **2026-11-16** — Assumed: `AUDIO_DATA` goes into `app_privacy_details.json` on main, because the daily's line-up note said PR #136 merged.
- **2026-11-16** — Assumed: the build starts now from main, before *Delete like Apple Notes* lands, and takes migration `0021`, because the person chose to publish and that change is not yet saved; whichever publishes second merges the other.
- **2026-11-16** — Assumed: a transcript is corrected only on the phone, in the note's own recording card, because the phone keeps the recording and its words; the web page and the Mac show it to read and copy.
- **2026-11-16** — Assumed: *Record* in a new note with no words yet makes the note with the recording under where the words go, because the person tapped *Record* in that note, not *New note*.
- **2026-11-16** — Assumed: a failed recording's reason stays in memory only, and the next open writes its words again, because the reason stays on the phone and the store keeps only "no words yet".
- **2026-11-16** — Assumed: a ring note's recording on the web page shows as the note's top card with no transcript, because its words are already the note's text.
- **2026-11-16** — Assumed: the speech-model texts no longer say the voice never leaves the phone, and say the phone writes the words with no server, because recordings now go to the space while sending is on.
- **2026-11-16** — Assumed: when the space refuses a moved voice note's change because the note came from this phone's earlier key (`not_own`), the phone puts the words back as the note's text, clears the recording's transcript, and keeps the recording on this phone only (`here_only`, never sent), with no repeat send, because the space keeps its text, so nothing is lost and the words show once.
- **2026-11-16** — Assumed: the build saves on the worktree's branch `audio-note-transcript-layout`, because the branch already held the plan; the change keeps its name.
- **2026-11-16** — Asked: publish now and add *Audio Data* in App Store Connect later → the person said it is added already.
- **2026-11-16** — Assumed: archived at publish after the web page check passed; the device check could not build the app (GitHub's Mac failed to reach github.com), so the phone scenarios rest on the unit tests.
- **2026-11-16** — Assumed: the `recording-card` flow taps *Record* until the recording screen opens, and matches *Home* by its start, because the device check tapped *Record* while the speech model was still coming, then missed *Home* under its *1 waiting* line.
- **2026-11-16** — Assumed: on merging *Delete like Apple Notes*, its store step runs before this one (store version 16), *Copied* shows no message, and a deleted note hides *Record* and its transcript field, because that change removed every toast and makes a deleted note read-only.
