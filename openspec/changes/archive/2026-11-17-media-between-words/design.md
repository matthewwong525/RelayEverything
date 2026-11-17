# Design

## Context

`_page` in `mobile/lib/screens/note_editor.dart` builds a note as a column: the date, each `top` recording, one `QuillEditor` for the words, then each file and each other recording by `filesBefore`. The words are Markdown in `Entry.text` (`editor/markdown.dart` turns them to a Delta and back, byte for byte). A table is already a block embed in that Delta, written as a Markdown table, with `TableEmbedBuilder` drawing it. The phone, the web page (`web/web_relay.dart`) and the Mac app share this editor.

`PATCH notes` (`app/worker/apps/relay/edit-note.ts`) only adds files: it takes the note's whole list and adds the ones the server lacks, only for a note the calling device sent. No path removes a file; `recently-deleted.ts` deletes sealed files only when a note goes for good. The phone's pull (`store.dart`, `INSERT OR IGNORE INTO attachments`) only adds rows.

## Goals / Non-Goals

**Goals:** one editor holds words and files in order; a new file goes at the cursor; delete removes a file everywhere; Undo brings it back; old notes show as now until changed.

**Non-Goals:** drag to move a file; remove a file from another device's note; a new look for pictures, file rows or recording cards.

## Decisions

### A file's place is a Markdown line in the text

`markdownToDelta` reads a line that is only `![<name>](attachment:<id>)` as a block embed `{attachment: <id>}`; `deltaToMarkdown` writes it back the same. The name is for readers (AI apps, webhooks); the id is the key. A line whose id the note does not hold stays as plain words, so nothing is lost.

Alternative: a position number on each file (lines before it). Rejected: an edit on the Mac, the web page or by an AI app moves lines, and the number goes wrong.

### The page is one editor; files with no line are placed when it opens

`_page` keeps the date and one `QuillEditor`. An `AttachmentEmbedBuilder` draws `NotePicture`, `NoteFileRow` or `RecordingCard` by the id, from the open `Entry`'s files and recordings. When the editor loads a note, each file with no line gets a block where it shows today: a `top` recording at the start, the rest at the end in `filesBefore` order. These blocks do not count as a change: the note is saved only when the person changes it, and then every file has its line. `plainText` skips attachment embeds, so the list row, search and *Share* stay the same.

### A new file goes at the cursor

`NewFile` gets an `id` that the editor makes before it inserts the block, and the controller uses that id for the stored `Attachment`. *Attach* inserts one block for each picked file at the cursor's line (after it when the cursor is mid-line), or at the end with no focus, then saves. *Record* remembers the cursor's line, passes a new id to `startVoiceNote(into:, id:)`, and inserts the block when the recording is saved; the X inserts nothing. A file dropped in the browser goes at the end.

### Delete removes a file; Undo sends it again

On save, the editor compares the note's file ids with the ids in the Delta. A file id that is gone is removed: `Relay.editNote` gets `removed: [ids]`. The controller deletes the `attachments` row, drops any queued upload for it, and keeps the bytes until the page closes. Undo puts the block back; the next save finds an id the note no longer holds and adds the file again from the kept bytes, as a new file. When the page closes, the phone deletes the kept bytes of each file still removed. A note from another device has no delete for its blocks: the editor puts the cursor after the block and removes nothing.

Alternative: treat a file missing from `attachments` as removed. Rejected: an older app build that sends a short list would delete files.

### The server removes by explicit ids

`PATCH notes` takes `removed`, up to 10 ids, only for a note the calling device sent (else `not_own`). It deletes those `relay_attachments` rows and their sealed files (the code `recently-deleted.ts` uses), and logs one `note.updated`. A removed id the note lacks is skipped, so a resend is safe. `GET notes` lists the files the note holds now; the phone's pull deletes local rows for a pulled note that are no longer listed, and their bytes, except a file of this device's note still waiting to send.

## UX

### Use-case brief

Matthew writes a note on his iPhone, adds a photo or a recording, then keeps typing under it, as in Apple Notes. Common case: one or two pictures or recordings in a note, with words between them. Edge cases: an older note with no file lines; a note from another device; Undo after a delete.

### Flow

Tap where the file goes → *Attach* or the mic → the file shows at that line → type under it. To remove: put the cursor after it → delete.

### Hierarchy

The note's words stay the one primary thing; files are blocks in the words. No new button.

### Review

[review.html](review.html): the What Changes item *Photos, files and recordings sit inside the note's words* shows the note page before and after.

### Components

Existing: `NotePicture`, `NoteFileRow`, `RecordingCard`, the `QuillEditor` with `TableEmbedBuilder` as the model. New: `AttachmentEmbedBuilder`, which draws the existing parts as embeds.

## Risks / Trade-offs

- A recording card inside the editor holds taps (play, waves, transcript field). The table embed already does this; the card must stop the editor from taking its taps and focus.
- Webhook and AI readers see the new `![…](attachment:…)` lines in `text`. This is Markdown, as the text already is.
- Undo after a delete sends the file again: a removal and a new add, two `note.updated` messages.
