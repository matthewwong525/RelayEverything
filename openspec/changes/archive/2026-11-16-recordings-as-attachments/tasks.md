# Tasks

Start from the newest main. The *Delete like Apple Notes* change (Recently Deleted) is not on main yet and takes space migration `0020`; this change takes `0021`, and whichever publishes second merges the other's edits to the same server and phone files. If the *Apple-style note toolbar* change landed first, put *Record* in its new bar. If the *Simplify Relay Everything webhooks* change landed first, put the recording fields on its two paths only: the server's send when signed in, the phone's send with no account. Start from the prototype's diff, `.scratch/recordings-as-attachments-prototype.diff`: it holds `RecordingCard`, the *Record* buttons, `Entry.recordings` and the row title as drawn on the review page.

## 1. Server

- [x] 1.1 Add the next free space migration (`schema/space-migrations/0021_recording_transcripts.sql`; `0020` is Recently Deleted's): `relay_attachments.transcript TEXT`, `length_ms INTEGER`, `top INTEGER NOT NULL DEFAULT 0`, and a trigger that moves the note's `relay_note_changes` row when either changes. Document it in `wiki/relay-space-migrations.md`. Verify: a schema test runs it on old rows and shows the new columns and a moved change row on a transcript update.
- [x] 1.2 `add-note.ts` and `edit-note.ts`: files take optional `transcript` (≤ 100 000 chars), `lengthMs` and `top`; `PATCH notes` updates a known file's transcript under the `edited_at` rule and logs one `note.updated`; the same transcript logs nothing. Verify: tests in `edit-note.test.ts` and `api.test.ts`.
- [x] 1.3 `queries.ts`: `FILES` gives `transcript` and `lengthMs`; the `words` filter also matches transcripts. `note-sync.ts`, `relay-mcp/tools.ts` and `api-doc.ts` carry the fields; no route gives a file's bytes to an agent key. Verify: `queries.test.ts`, `note-sync.test.ts`, connector tests.
- [x] 1.4 `webhooks/format.ts`: `attachment` gets `transcript` (string or null) and `length_ms`; run `npm run relay:api-doc` in `app/`. Verify: `format.test.ts` and the example receiver's test pass with the new fixtures from 2.6.

## 2. Phone data

- [x] 2.1 `data/store.dart`: `Attachment` gets `lengthMs`, `transcript`, `wordsPending`, `top`; a new store version moves each voice note as design.md says, once. Verify: `store_test.dart` covers a sent, an unsent, a pending, a failed, a missing-file and a no-words watch note, and a second open that moves nothing.
- [x] 2.2 `voice/recorder.dart` and `controller.dart`: a recording is kept as `attachments/<id>.wav` on its note; the words queue, failed map and *Try again* are keyed by attachment; `keepRecording` adds to a new or an open note; the note waits for pending words, then sends; a transcript edit sends a `PATCH`. Verify: `controller_test.dart` and `voice_test.dart` keep a note with two recordings, send it once both have words, and send a corrected transcript.
- [x] 2.3 `relay.dart`: `Entry.recordings` replaces `voice`, `recording` and `length`; `files` holds only other files. Update every reader. Verify: `flutter analyze` is clean.
- [x] 2.4 `data/api.dart` and `data/note_sync.dart`: send and read `transcript` and `lengthMs`; a synced recording downloads on play. Verify: `note_sync_test.dart`, `sync_test.dart`.
- [x] 2.5 Shortcuts (`shortcuts/`, `RelayIntents.swift` path unchanged) and the watch inbox: given words become the note's text and the recording one attachment. Verify: `shortcuts_test.dart`.
- [x] 2.6 `data/webhook.dart`: the phone's own webhook (with no account) lists `transcript` and `length_ms`; `webhook_test.dart` writes the fixtures. Verify: `webhook_test.dart`.

## 3. Phone screens

- [x] 3.1 `screens/note_blocks.dart`: `RecordingCard` (player, hairline, *Transcript* folded to 2 lines, open with copy and an editable field, *Writing the words…*, the failed line with *Try again*, *No words heard*). Verify: `screens_test.dart` folds, opens, copies and edits a transcript.
- [x] 3.2 `screens/note_editor.dart`: the `top` recording above the words with *Add notes…* under it, every other recording after the words with the pictures and files in list order, the note's text no longer filled from words. `screens/note_bars.dart`: *Record* in both bars on a phone only, hidden for a note from elsewhere, refused at 10 files. Verify: widget tests for each.
- [x] 3.3 `screens/timeline.dart`, `days.dart`, `folder.dart`: title from typed words else the first transcript; mic and the first length; *Voice* filter by "has a recording"; search reads transcripts. Verify: `screens_test.dart` row and search tests.
- [x] 3.4 Web and Mac (`web/`, Mac shell): `RecordingCard` with a plain line, play from the space, *Still on your phone* before the bytes arrive, no *Record*. Verify: `web_relay_test.dart`, `mac_shell_test.dart`.
- [x] 3.5 Write a Maestro flow in `mobile/device-check/flows/` that opens a seeded voice note, opens its transcript and types a note under it.

## 4. Website

- [x] 4.1 `site/src/content/docs/privacy.md`, `app/voice-notes.md`, `app/your-notes.md`, `app/on-a-computer.md`, the webhooks page: recordings go to your space like files while sending is on; transcripts; the mic in a note; the webhook fields. Verify: `node scripts/product-name.test.mjs` passes.

## 5. App Store

- [x] 5.1 Add an `AUDIO_DATA` entry (`APP_FUNCTIONALITY`, `DATA_LINKED_TO_YOU`, no tracking) to `mobile/ios/fastlane/app_privacy_details.json` (on main since PR #136). Verify: the file is valid JSON and lists `AUDIO_DATA` once.
- [x] 5.2 The person adds *Audio Data* (App Functionality, linked to the person, not used for tracking) in App Store Connect's App Privacy page before the next release. Name this step in the build's report.

## 6. Checks

- [x] 6.1 Run `flutter analyze` and `flutter test` in `mobile/`, and `npm test` and `npm run lint` in `app/`; all pass.
- [x] 6.2 Run `/save`; on its preview, open a note with two recordings on the web page, play one, and read its transcript.
