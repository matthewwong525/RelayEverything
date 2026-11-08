# Proposal: Send a note's files to your own database

**Status:** ready-to-ship
**Branch:** webhook-note-files
**Open questions:** none

## Why

Milestone 1 says nothing is lost on the way to your own database. Today a note's photos and PDFs never get there from the Relay Everything server: the webhook names each file but holds no bytes, and the website's example receiver drops even the names. This plan changes a decision in the webhooks spec, which said only the phone, when it sends to your own webhook, sends a file's bytes.

## What Changes

- **Each file follows its note.** When a file of a note is stored, every webhook gets it in its own `note.file` message, after the note: the same message the phone already sends to your own webhook. So one receiver works for both. Retries, *Try again now*, pause and *Send past data* work for files as they do for notes.
  ```mermaid
  sequenceDiagram
    participant P as Phone
    participant R as Relay Everything
    participant D as Your database
    P->>R: Note, with its file names
    R->>D: note.created (names)
    P->>R: The file's bytes
    R->>D: note.file (bytes)
  ```
- **A file too big for your receiver is skipped, not stuck.** A file can be 25 MB, which makes a message of about 33 MB. When your receiver answers *413 too large* to a file, Relay Everything sends the rest and the webhook's card names the skipped file, as the phone does. The file stays on your Relay Everything page. Every other failed answer is tried again, as today.
- **Files you already have reach your database once.** After this goes live, each webhook gets the files already stored, so the gap closes for notes sent before.
- **The example receiver keeps every file.** It saves each name from the note, then the bytes when they come, so a file that never arrives still shows as listed.
- **The website says so.** The *Your own database* page says the server sends `note.file` too, and how big a body to accept.

Non-goals: a web API route or AI tool that opens a file; photos and chats webhooks; a change to the phone's own-webhook mode.

## What the build needs

- **Nothing.**

## Decision log

- **2026-11-07** — Assumed: the server sends each file as `note.file`, not a download link in `note.created`, because a link needs a new receiver login, runs out during a day of retries, and gives receivers a second shape beside the phone's.
- **2026-11-07** — Assumed: this changes the spec decision that only the phone sends `note.file`; in alpha, version 1 may change in place, and the docs already tell receivers to answer 2xx to a type they do not know.
- **2026-11-07** — Assumed: a `413` answer to a `note.file` skips that file and shows it on the card, as the phone's own-webhook mode does, because one big file must not hold back every note after it.
- **2026-11-07** — Assumed: files stored before this change are logged once when it goes live, so each webhook gets them, because Milestone 1 needs Matthew's earlier files in WongOS; a webhook made after a note may get that note's file without the note.
- **2026-11-07** — Assumed: `note.file` belongs to the Notes kind, so it goes to every webhook with no new tick; the Files kind keeps its webhook part listed as missing, with a reason that points at Notes.
- **2026-11-07** — Assumed: the server builds a file's message as bytes, not one long text, because a 25 MB file as base64 text and its copies can pass a Worker's 128 MB of memory.
- **2026-11-07** — Assumed: `POST attachments` wakes the webhooks after it seals a file, as `POST notes` does, because the design names no wake and a file would otherwise wait up to 15 minutes for the space's alarm.
- **2026-11-07** — Assumed: the worker declares the one `node:crypto` function it uses, `createHmac`, in `app/worker/node-crypto.d.ts`, beside `sql.d.ts`, because the worker's types hold no Node types and adding all of them could clash with the Workers types.
- **2026-11-07** — Assumed: the card names a skipped file until the next message the address takes, as every last answer does; each try in the send history keeps the skip's words.
- **2026-11-07** — Assumed: `format.test.ts` no longer checks that no server code builds `note.file`; that test guarded the removed requirement, so it now checks the server's builder instead. No check was loosened.
- **2026-11-07** — Built inside /ship: migration, server sender, receiver, docs and wiki; the second look found nothing to fix; specs reconciled; saved for the staging check (task 4.2).
- **2026-11-08** — Assumed: task 4.2 passed on staging with the branch's spaces Worker and shared server deployed by hand: a 25 MiB file and a photo reached the example receiver with matching SHA-256, a 413 receiver skipped only the files and got the next note, with the skip named, and migration 0007 ran with no errors. The one-time log of files stored before 0007 was not run on staging; `migration.test.ts` covers it.
- **2026-11-08** — Archived for publish inside /ship: CI passed, every task is ticked, the staging check passed, and specs were already reconciled.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-webhooks`: the server's webhooks send `note.file` for each stored file after its note, skip a file on `413`, and send files stored before the change once; the example receiver keeps a note's file list.

## Impact

- **Space migration** (`schema/space-migrations/0007_note_files.sql`): `relay_outbox` takes the `note.file` kind; a trigger logs a file when its bytes are sealed; stored files are logged once.
- **Server** (`app/worker/apps/relay/`): `kinds.ts` (Notes owns `note.file`, a file builder, the Files reason), `webhooks/format.ts` (descriptions, a `noteFile` builder), `webhooks/send.ts` (a body built as bytes, `413` skips a file), `webhooks/sign.ts` (signs bytes), the card's last-answer text in `webhooks/routes.ts`.
- **Website** (`site/`): `connections/your-database.md`, `public/webhooks/v1.schema.json` (from `npm run relay:api-doc`), `public/webhooks/receiver.mjs`.
- **Wiki**: `wiki/relay-spaces.md` *Webhooks*.
- **Sample data**: `app/tests/relay-space-rows.sql` or `schema/seed.sql` holds a note with a stored file.
