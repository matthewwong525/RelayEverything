# Design: Shortcuts actions and files on notes

## Context

See [proposal.md](proposal.md) for why. Today:

- **The phone app** (`mobile/`, Flutter) keeps notes in its own SQLite file through drift (`lib/data/store.dart`, schema 4). `RelayController.addNote` saves, pins (`_pinThenSync`) and queues an upload in the `outbox` table only while sending is on. `lib/data/outbox.dart` sends JSON bodies oldest first through `RelayApi.post`. The iOS target is iOS 15. `AppDelegate.swift` already runs a second engine for Workmanager's hourly sync and a `relay/files` method channel.
- **The server** keeps a note in the person's space (`relay_notes`, `schema/space-migrations/`). A ring recording is sealed with AES-GCM in `RELAY_BUCKET` under `people/<person>/…` through `space.files` (`space.ts`); only `space.ts` may name the bucket ([person spaces](../../../wiki/relay-spaces.md)). `audio.ts` opens one for its person. `deleteEverything` removes the space and every object under the person's prefix.
- **Webhooks** send `note.created` (format v1, `webhooks/format.ts`) with the recording inline as base64.

## Goals / Non-Goals

**Goals:** App Intents that run the app's own Dart save path; a note's file list on the phone, in the outbox, in the space and on the page; webhook metadata for files.

**Non-goals:** a share extension; Mac Catalyst; chunked or resumable upload; files through the AI connector or the planned `/v1/` API; editing a note's files.

## Decisions

### 1. App Intents in Swift call Dart in a background engine

`ios/Runner/RelayIntents.swift` declares `AddNoteIntent`, `GetNotesIntent` and `StartVoiceNoteIntent`, and `RelayShortcuts: AppShortcutsProvider` gives each a Siri phrase. Each is `@available(iOS 16, *)`, so the app keeps iOS 15.

*Add a note* and *Get notes* set `openAppWhenRun = false`. Their `perform()` uses one shared `ShortcutsEngine`: a `FlutterEngine` started on the Dart entry point `shortcutsMain` (`lib/shortcuts/entry.dart`, `@pragma('vm:entry-point')`), with the plugins registered, kept alive while the process lives. Swift calls the `relay/shortcuts` method channel: `add` with `{text, files: [{path, name, type}]}`, `get` with `{limit, query, since}`. Dart builds a `RelayController` on the same store and answers. When the app's own engine is running, the call goes to it instead, so the open timeline shows the note at once.

`IntentFile`s are copied into the app's `attachments/` folder before the call, because the system deletes its own copy after `perform()` returns.

*Alternative:* Swift writes into the SQLite file, or into an inbox the app drains on its next open. Rejected: the first writes a second copy of save, pin and outbox; the second leaves an automation's note unsent until the app opens. The inbox stays as a fallback only: when the engine does not answer in 20 seconds, Swift writes the request to `shortcuts-inbox/` and says *Saved. It shows when you open Relay Everything.* `RelayController.load` drains it.

*Start a voice note* sets `openAppWhenRun = true` and posts `startVoiceNote` on the app's own channel; Flutter opens a tap-to-stop recording sheet that calls the controller's existing `startVoiceNote` / `endVoiceNote` / `cancelVoiceNote`.

*Get notes* returns `[RelayNoteEntity]`, an `AppEntity` with words, time, place name, kind and files as `IntentFile`s, so Shortcuts can pass each part on.

### 2. Files on the phone: one table, one outbox route each

Schema 5 adds `attachments (id TEXT PRIMARY KEY, note_client_id TEXT NOT NULL, name TEXT, type TEXT, size INTEGER, path TEXT, sent_at INTEGER)`. A file is copied into `attachments/<id>` in the app support folder. Files stay in iCloud backup.

A note's `notes` upload body gains `attachments: [{id, name, type, size}]`. Each file then gets its own outbox row, route `attachment`, body `{noteClientId, id, path, name, type}`, queued after the note's row. `flush` sends `attachment` rows with `RelayApi.upload`, which posts the file's bytes with the metadata in headers. Order holds, so a file never reaches the server before its note. *Send them* queues earlier files the same way.

The paperclip uses `file_picker` (photos and files); the timeline opens a file with `open_filex`. Limits (10 files, 25 MB) are checked in the controller, so the paperclip and Shortcuts share them.

### 3. Files in the space: a table and a sealed object per file

`schema/space-migrations/0003_attachments.sql` adds `relay_attachments (id TEXT PRIMARY KEY, note_id TEXT NOT NULL, name TEXT NOT NULL, content_type TEXT NOT NULL, size INTEGER NOT NULL, file_key TEXT, created_at INTEGER NOT NULL)`. `notes.ts` inserts one row per listed file with `file_key` NULL, in the same call as the note.

`POST attachments` (`attachments.ts`, `asDevice`, phone reach): headers `X-Note-Client-Id`, `X-Attachment-Id`, body the raw bytes, at most 25 MB. It finds the row through the device's note, seals the bytes with `space.files.put` at `people/<person>/attachments/<id>`, and sets `file_key`. A row that already has its file answers `added: false`: a resend is stored once. A file that is not listed on its note gets 404.

`GET attachment?id=` (`asPerson`) opens the file and answers it with its `Content-Type` and `Content-Disposition: attachment; filename=…`, or `inline` for `image/*`. `queries.ts`/`timeline.ts` return each note's files with `ready: file_key IS NOT NULL`.

Account delete needs no new step: the key is under the person's prefix. `space-access.test.ts` keeps passing, because only `space.ts` touches the bucket.

### 4. Webhooks: a list, version 1

`format.ts` gives `note` an optional `attachments` array of `{id, name, content_type, size}`. `noteCreated` adds it only when the note has files. The public schema is regenerated. `site/…/your-database.md` says that a message may gain optional fields within a version. The message goes when the note is stored; it does not wait for the files, as it carries no bytes.

## UX

### Use-case brief

You, on the iPhone, want something into Relay Everything with the fewest taps, or none: a thought by Siri, a screenshot, a receipt. Done is the note in your timeline with its files, and on your page if you send. Common case: an automation with no screen at all. Edge cases: no words, a file too big, sending off.

### Flow

- Shortcut: *Add a note* → nothing to see → the note is in the timeline next time you look.
- Action button: press → recording sheet → *Stop* → voice note in the timeline.
- In the app: *New note* → type → paperclip → pick → *Save*.

### Hierarchy

- **New note:** *Save* stays the one primary action; the paperclip is a quiet button under the text; each file is a small chip with a remove cross.
- **Timeline card:** words first; pictures as a row of thumbnails; other files as one line each, name and size.
- **Recording sheet:** *Stop* is primary, *Cancel* quiet, the time counting up.
- **Page note card:** as today, with one row of files under the words.

## Risks / Trade-offs

- [A background engine may be slow to start, or iOS may stop the intent at about 30 seconds] → the engine stays warm while the process lives, and the 20-second fallback inbox keeps the note.
- [Two engines share one SQLite file] → drift opens it in WAL mode with a busy timeout; only one sync runs, because the controller's sync lock is per engine, and the server's `ON CONFLICT` keeps a double send to one note.
- [A 25 MB file held in a Worker's memory twice, plain and sealed] → about 50 MB, under the 128 MB limit; uploads are one at a time per phone.
- [A receiver that refuses unknown fields breaks on a note with files] → the field appears only then, and the webhook page says so.
- [The paperclip and file opening add two packages] → both are widely used and add no network call.

## Migration Plan

Deploy order, as [the Workers and their order](../../../wiki/relay-spaces.md#the-workers-and-their-order) says: the spaces Worker with `0003_attachments.sql`, then the server. An older phone sends notes with no `attachments` field and works as before. The new phone needs the new server for files. An old server refuses a note body with an unknown `attachments` field with 400, so on a 400 for a note that lists files the phone sends that note once more without the list. The note lands, each `attachment` upload then gets 404 and is dropped, and the note stays sent. A note the server refuses twice is dropped, as any refused body is.

## Open Questions

- Resolved: the `AppShortcutsProvider` and the three intents live in the Runner target. App Intents run in the app's own target from iOS 16, so no extension is needed, and the actions share the app's support folder with no App Group. `AppIntents` is weak-linked, so the app still opens on iOS 15. The Mac check's `flutter build ios --simulator` confirms the build.
