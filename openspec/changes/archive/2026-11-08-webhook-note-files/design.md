# Design

## Context

The sender (`app/worker/apps/relay/webhooks/send.ts`) reads each webhook's place in the send log, `relay_outbox`, builds one message per group through the owning kind in `kinds.ts`, and moves its place only after a 2xx. Log rows come from triggers in the space migrations; `relay_outbox.kind` has a `CHECK` that names every log kind (last rebuilt in `0006_phone_data.sql`).

A note's files are `relay_attachments` rows, listed when the note arrives with `file_key` NULL. `POST attachments` (`attachments.ts`) seals the bytes, up to `MAX_FILE_BYTES` (25 MB), and sets `file_key`. `note.created` lists the rows; nothing sends the bytes. The phone's own-webhook mode (`mobile/lib/data/webhook.dart`) already sends `note.file` after each note and drops one file on a 413.

## Goals / Non-Goals

**Goals:** every stored file reaches every webhook, in order after its note, with the same retries; a body that fits in a Worker's memory; one receiver shape for the server and the phone.

**Non-Goals:** a file download route or AI tool; changes to the phone; photos and chats webhooks.

## Decisions

### Log a file when its bytes are sealed

Migration `0007_note_files.sql` rebuilds `relay_outbox` with `note.file` in its `CHECK`, by the copy pattern in `0006` (keep every `seq`, drop and make again the triggers that write the log). A new trigger, `AFTER UPDATE OF file_key ON relay_attachments WHEN old.file_key IS NULL AND new.file_key IS NOT NULL`, logs `('note.file', new.id, <the note's recorded_at>, now)`. `at` is the note's time, so *Send past data* picks a file with its note. The note's own `note.created` row always has a lower `seq`, as a file is listed only on a stored note.

The migration then logs each file already sealed, ordered by its note's `recorded_at`, so each webhook sends it once.

Alternative: put a download link in `note.created`. Rejected: a receiver needs a new credential, a link must outlive about 22 hours of retries, and the phone's mode has no server to link to.

### Notes owns `note.file`

`KINDS` notes: `log: ["note.created", "note.updated", "note.file"]`. Its `build` branches on the entry's kind: a `note.file` row reads the attachment and its note's id, opens the bytes with `files.open`, and returns `skip` when the row or the bytes are gone (the note was deleted). `groupOf` already sends any `note.*` entry alone. The Files kind keeps `missing.webhook`, with the reason *A file goes with its note as note.file, under Notes.*; `kinds.test.ts` stays as it is.

### Build the body as bytes

A 25 MB file is about 33 MB of base64. A JS string of it, plus `JSON.stringify` and the signing copy, can pass 128 MB. So `format.ts` gains `noteFile(row, noteId, at)`, which builds the message with `base64: ""`. The sender serialises it, splits at the empty value, and writes prefix, base64 and suffix into one `Uint8Array` of exact size; the base64 is written in 3-byte-aligned chunks. `sign.ts` signs bytes with `node:crypto`'s `createHmac`, fed `"{id}.{timestamp}."` and then the body, so no second copy exists. `post` takes a string or bytes. Peak memory is about the file, plus its sealed copy while it opens, plus the body: under 100 MB for a 25 MB file.

### A 413 skips the file

In `step`, a 413 answer to a `note.file` records the try, then advances past the group with `last_error` set to *Too large for this address: <name> (<size>). It stays on your Relay Everything page.* The card already shows `lastError`. Every other answer follows `failed` as today. A `note.created` that answers 413 is retried as before.

### The example receiver keeps the list

`receiver.mjs` inserts each `note.created` attachment into `files` with `bytes` NULL (`ON CONFLICT DO NOTHING`), and `note.file` upserts with its bytes, keeping the row's id. Its comment drops *Only a phone…*.

## Risks / Trade-offs

- **Old receivers get a new type.** In alpha, version 1 may change in place, and the docs tell receivers to answer 2xx to unknown types; the example receiver keeps it as a raw row.
- **A webhook made after a note gets that note's earlier file** from the one-time log of stored files. It is rare (only alpha spaces) and harmless; the receiver stores the file by its note id.
- **Large bodies.** A host that takes small bodies answers 413, and the file is skipped rather than lost from Relay Everything. Staging checks a 25 MB file end to end.
- **A table rebuild** on every space at the next open. `migration.test.ts` checks that seqs, places and triggers survive, as it did for `0006`.
