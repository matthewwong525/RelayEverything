# Proposal

**Status:** built; final checks running
**Branch:** `allow-text-after-media`
**Open questions:** none

## Why

In a note today, the words are one block, and photos, files and recordings always sit after it (a voice note's first recording sits above it). You can't type under a photo or between two recordings, so a note can't read top to bottom as you made it. Apple Notes lets you do this, and the phone app follows Apple Notes.

## What Changes

- **Photos, files and recordings sit inside the note's words.** Each one is a block in the note, as a table is now. You can type above it, below it and between two of them. The note keeps this order on the phone, the Mac app and the web page.
  ```page
  Before: pages/before.html
  After: pages/after.html
  ```
- **A new photo, file or recording goes where the cursor is.** With the keyboard down, it goes at the end of the note. This also applies to the mic: a new recording no longer always goes at the bottom.
- **Delete removes a photo, file or recording.** Put the cursor after it and press delete, as in Apple Notes. Undo brings it back while the note is open. The file goes from the note on every device and from your space. This is the first way to remove a file from a note. You can remove media only from a note you made on this device, as you can add media only to it.
- **Older notes keep their look until you change them.** A note made before this change shows a voice note's first recording at the top and the rest after the words, as now. You can type after them at once. The new order is kept when you next change the note.
- **AI apps and webhooks see where each file sits.** The note's text holds one line for each file at its place, such as `![board.jpg](attachment:…)`. The list of files in a webhook message stays the same.

## What the build needs

- **Nothing.**

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-attachments`: files sit at a place in the note's words, a new file goes at the cursor, the person can remove a file, and the note's text marks each file's place.
- `relay-notes-screen`: the note page shows each recording, picture and file where it sits in the words, not above or after them.
- `relay-voice-notes`: a recording from the mic goes at the cursor, not always at the bottom.

## Impact

- Phone app (`mobile/`): `editor/markdown.dart` reads and writes a file line as an editor block; `screens/note_editor.dart` builds the page from one editor, with block builders for pictures, file rows and recording cards; `controller.dart`, `data/store.dart` add, place and remove a note's files; `web/web_relay.dart` the same for the web page and the Mac app.
- Server (`app/worker/apps/relay/`): `PATCH notes` takes `removed`, the ids of files to remove; the server deletes their rows and sealed files and sends `note.updated`. `GET notes` already lists all files, so phones drop a removed one on the next sync.
- API doc (`npm run relay:api-doc`), the website's notes page, and the wiki's [person spaces](../../../wiki/relay-spaces.md) page.
- Non-goals: drag a photo to a new place; remove a file from a note made on another device; change the look of a picture, file row or recording card.

## Decision log

- **2026-11-17** — Asked what delete does after a photo, file or recording → chose it removes it from the note everywhere, and Undo brings it back while the note is open.
- **2026-11-17** — Asked where a new photo, file or recording goes → chose at the cursor, at the end with the keyboard down. This replaces the choice of 2026-11-16 that a mic recording goes at the bottom.
- **2026-11-17** — Assumed: each file's place is a Markdown line in the note's text, `![name](attachment:<id>)`, because the text already holds tables and styles as Markdown, so the place stays right when the words change on any device, and AI apps see where each file sits. A position number kept beside each file would go wrong after an edit on the Mac or the web page.
- **2026-11-17** — Assumed: a file with no line in the text shows where it shows today, because older notes, notes from Shortcuts and the watch, and an AI edit that drops a line must still show every file.
- **2026-11-17** — Assumed: a removal goes to the server as an explicit list of ids in `PATCH notes`, not as a file missing from the list, because an older app that sends a short list must never delete a file.
- **2026-11-17** — Assumed: Undo after a removal sends the file again from this device's copy, because the server deleted it; a file whose bytes are not on this device can't come back by Undo.
- **2026-11-17** — Assumed: blank words keep only the file lines, because an empty note with files is still a note of files, and stray empty lines would show as words.
- **2026-11-17** — Assumed: a removal waits in the phone's own store and goes with each change of the note until a pull no longer lists the file, because a lost answer must not keep the file on the server.
- **2026-11-17** — Assumed: a file both listed in `attachments` and named in `removed` is removed, and a change with only `removed` counts as a change, because the removal is the newer intent.
- **2026-11-17** — Assumed: a removal made while the note's first upload still waits is not sent, because the server does not have the file yet; the note goes without it.
- **2026-11-17** — Assumed: on the web page and the Mac app, Undo after a removal shows the file's line but can't bring the file back, because they keep no copy of the bytes.
- **2026-11-17** — Assumed: a file or recording with no id, or an id that cannot make a line, such as a ring note's recording in the browser, shows above or below the words as today, because it has no line to place it by.
- **2026-11-17** — Assumed: the webhook test for the files left after a removal sits in `webhooks/send.test.ts`, beside the other `note.updated` tests.
- **2026-11-17** — Assumed: the Maestro flow types its title, then picks the first photo in the simulator's own iOS picker by its "Photo, <date>" label; the device check adds no photos, so it uses the simulator's sample photos.
- **2026-11-17** — Check: the widget test that measured the recording card above the editor now finds the card inside the editor's words and checks it is still first, because the card moved into the words; what it proves stays the same.
- **2026-11-17** — Assumed: a note left with blank words and its last file just removed keeps the removal first, then is dropped as a bare note, because a note that still stays, such as a voice note, must not keep the removed file.
- **2026-11-17** — Assumed: words that still end up on a file's line by a path the editor does not catch are kept as a line of their own when the note is kept, never dropped, because lost words can't come back.
- **2026-11-17** — Assumed: the second look's four findings (a removed recording left its note waiting, pasted words beside a file were lost, an emptied note stayed on leave, no test for a recording at the cursor) are fixed with tests, because each is in the plan's scope.
