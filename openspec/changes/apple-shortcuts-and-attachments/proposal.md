# Add notes and files from Apple Shortcuts

**Status:** in-progress
**Branch:** apple-shortcuts-notes
**Open questions:** none

## Why

Today you can add a note only by typing or talking in the app, or with the ring. Apple Shortcuts lets you put Relay Everything in Siri, the Action button, and automations that run on their own, such as *when I get to work* or *each evening*. You also want to feed in more than words: photos, screenshots, PDFs and other files. So notes can now hold files too.

## What Changes

- **Relay Everything actions in Shortcuts.** The Shortcuts app gets three Relay Everything actions: *Add a note*, *Get notes* and *Start a voice note*. You find them in a shortcut, in Siri (*Add a note to Relay Everything*), in Spotlight, and on the Action button. They need the iPhone app and iOS 16 or later. They need no key, and they follow your *Send to Relay Everything* setting.
  ```screen
  <div class="card col gap phone">
    <span class="muted">Shortcuts · Apps</span>
    <h3>Relay Everything</h3>
    <div class="field row gap"><span class="tag">Add a note</span><span class="grow"></span><span class="muted">text and files</span></div>
    <div class="field row gap"><span class="tag">Get notes</span><span class="grow"></span><span class="muted">for the next step</span></div>
    <div class="field row gap"><span class="tag">Start a voice note</span><span class="grow"></span><span class="muted">opens the app</span></div>
  </div>
  ```
  This sketch stands in for a picture: the Shortcuts app draws these rows itself, from the action names.
- **Add a note takes text and files.** Give it words, files, or both: a photo, a screenshot, a PDF, a link, the clipboard, or the output of the step before. It runs without opening the app. The note is kept on the phone at once, with a place if *Pin notes* is on. With sending on, it goes to your space in the same moment, with its files. The action gives the new note back, so the next step can use it.
  ```mermaid
  flowchart TD
    A["Shortcut: text and files"] --> B["Add a note"]
    B --> C["Kept on the phone"]
    C -->|sending on| D["Your space"]
    D --> E["Your webhooks"]
    C -->|sending off| F["Stays on the phone"]
  ```
- **Get notes gives notes to the next step.** Pick how many, words to look for, or a start time. You get each note's words, time, place and files. It reads only the notes on this phone and sends nothing.
  | Choice | Example |
  | --- | --- |
  | Newest | The last 5 notes |
  | Holds words | Notes that say *groceries* |
  | Since | Notes from today |
  | What you get | Words, time, place, files, and whether it is a voice note |
- **Start a voice note opens the app and records.** It is made for the Action button: press, talk, tap *Stop*. With no speech model yet, the app asks to get it first, as today.
  ```screen
  <div class="card col gap phone">
    <h3>Recording</h3>
    <span class="muted">0:07</span>
    <span>Talk now. Tap Stop to save, or Cancel.</span>
    <div class="row gap"><button class="btn-ghost">Cancel</button><span class="grow"></span><button class="btn-primary">Stop</button></div>
  </div>
  ```
  This sketch stands in for a picture: the phone app does not run in the plan's preview.
- **You build automations from these.** The website gets a *Shortcuts* page with ready recipes, each with its steps.
  | When | Do |
  | --- | --- |
  | You arrive at work | Add a note *At work* |
  | You take a screenshot | Add a note with the screenshot |
  | Each evening at 9 | Get notes since today, then send them to yourself by email |
  | You tap an NFC tag | Add a note *Fed the cat* |
  | You press the Action button | Start a voice note |
- **Notes can hold files.** *New note* gets a paperclip button: add photos or files from the phone. A note holds up to 10 files, each up to 25 MB, of any kind. The timeline shows pictures small, and other files as a row with name and size. Tap one to open it. A note can be only files, with no words.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">Cancel</button><span class="grow"></span><h3>New note</h3><span class="grow"></span><button class="btn-primary">Save</button></div>
    <div class="field"><span>Receipt for the desk lamp</span></div>
    <div class="row gap"><span class="tag-outline">receipt.jpg · 1.2 MB</span><span class="tag-outline">warranty.pdf · 240 KB</span></div>
    <div class="row gap"><button class="btn-ghost">Add photo or file</button></div>
  </div>
  ```
  This sketch stands in for a picture: the phone app does not run in the plan's preview.
- **Files go to your space, locked like recordings.** With sending on, each file goes after its note, and *Send them* sends earlier files too. In your space, each file is locked with your space's own key, as ring recordings are. Your Relay Everything page shows pictures in the note and other files as a link to download. Deleting your account deletes them.
  ```screen
  <div class="card col gap">
    <div class="row gap"><span class="tag">Typed</span><span class="muted">iPhone · 9:14 · Main St</span></div>
    <span>Receipt for the desk lamp</span>
    <div class="row gap"><span class="skeleton">picture</span><span class="tag-outline">warranty.pdf · 240 KB · Download</span></div>
  </div>
  ```
  This sketch stands in for a picture: it adds one row of files to the note card you know.
- **Webhooks get each file's name, type and size, not the file.** A file can be 25 MB, too big for one message. A note with files has a new `attachments` list in its `note.created` message. A note without files gets the same message as today.
  | Field | Example |
  | --- | --- |
  | `name` | `warranty.pdf` |
  | `content_type` | `application/pdf` |
  | `size` | `245760` |
- **The website says how.** A new *Shortcuts* page, and the notes, privacy and webhook pages name files.

Non-goals: Shortcuts on a Mac or on Android; a *Share to Relay Everything* button in other apps; an AI app or the new web API reading files; editing or removing a file after the note is saved; files in a ring note.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are in `.env`.
- **App Store Connect key for TestFlight builds**: Ready, in `.env` and the repository's secrets.
- **Your iPhone with TestFlight**: Ready, you have the app. After the build you make one shortcut and see the note on your page.

## Capabilities

### New Capabilities

- `relay-shortcuts`: the iPhone app's Shortcuts actions: add a note with text and files, get notes, start a voice note.
- `relay-attachments`: files on a note, on the phone, in the person's space, on the page, and in webhook messages.

### Modified Capabilities

None.

## Impact

- `mobile/ios/Runner/`: new Swift App Intents (`RelayIntents.swift`), an App Shortcuts provider, a headless Flutter engine for intents, `Info.plist` words; `AppDelegate.swift` drains the intent inbox channel.
- `mobile/lib/`: a new `shortcuts/` folder (inbox drain, the intent entry point `shortcutsMain`), `data/store.dart` (schema 5: `attachments` table, outbox `attachment` route), `data/outbox.dart` and `data/api.dart` (file upload), `controller.dart`, `screens/compose.dart` (paperclip), `screens/timeline.dart` (files), `screens/hold_to_talk.dart` (tap-to-stop recording screen). New package `file_picker`, `open_filex`.
- `app/worker/apps/relay/`: new `attachments.ts` (`POST attachments`, `GET attachment`), `notes.ts` (note takes a file list), `queries.ts` and `timeline.ts` (files per note), `webhooks/format.ts` and `send.ts` (`attachments`), `account.ts` (delete covers them).
- `schema/space-migrations/0003_attachments.sql`: `relay_attachments`.
- `app/src/apps/relay/Notes.tsx`: pictures and download links.
- `site/`: `app/shortcuts.md`, `app/your-notes.md`, `privacy.md`, `connections/your-database.md`, `public/webhooks/v1.schema.json`, `api/reference.md` (`npm run relay:api-doc`). `scripts/product-name.test.mjs` lists the new page.
- Overlap: the plan `relay-api-and-connector-add` also edits `notes.ts`; whichever ships second rebases.

## Decision log

**2026-11-07** — Asked how Shortcuts should talk to Relay Everything → chose "Actions in the iPhone app (Recommended)": the app adds its own actions to Shortcuts, Siri and automations, offline, with no key.
**2026-11-07** — Asked which actions the app gives Shortcuts → chose Add a note, Get notes and Start a voice note, and Add a note takes text and attachments, so notes can hold files.
**2026-11-07** — Asked where a note's attachments go → chose "To your space too (Recommended)": kept on the phone, sent with sending on, sealed like recordings, shown on the page; webhooks get name, type and size.
**2026-11-07** — Asked what a note can hold → chose "Any file, up to 25 MB each (Recommended)".
**2026-11-07** — Asked whether you can attach in the app itself → chose "Yes, a paperclip button (Recommended)"; no share sheet in this change.
**2026-11-07** — Assumed: up to 10 files per note, because a cap keeps one shortcut from filling a space, and 10 covers a burst of photos.
**2026-11-07** — Assumed: the actions need iOS 16, and the app keeps iOS 15 without them, because App Intents start at iOS 16 and raising the minimum shuts out older phones for no gain.
**2026-11-07** — Assumed: *Add a note* runs the app's own Dart code in a background engine, so the note goes through the same save, pin and send as a typed note, and no second copy of that code is written in Swift.
**2026-11-07** — Assumed: webhook messages stay version 1 and a note with files gains an `attachments` list, because only a receiver that refuses unknown fields breaks, the field is absent on every other note, and the database page will say new fields can appear.
**2026-11-07** — Assumed: a file is stored and served whole, sealed like a recording, because 25 MB fits in a Worker's memory and one sealing path is simpler than chunks.
**2026-11-07** — Assumed: files on the phone stay in the iPhone's backup, unlike recordings, because a file you added may exist nowhere else.
**2026-11-07** — Assumed (build): the server stores a file's type only when it reads as a plain `type/subtype`, else `application/octet-stream`, and serves each file with `nosniff` and a sandbox, because the type comes from the phone and a page must never run a file as its own.
**2026-11-07** — Assumed (build): a device adds a file only to a note it sent itself; another device's upload for that note gets 404.
**2026-11-07** — Assumed (build): the AI connector's notes now list each file's name, type and size, as the timeline does, but never the bytes, because file names are part of the note and the connector shares the timeline's reads.
**2026-11-07** — Assumed (build): the two file routes get their own website page, `api/files.md`, as recordings have, because a bare route needs a page for the route reference.
**2026-11-07** — Assumed (build): a phone file keeps its extension (`attachments/<id><.ext>`), so the phone can open it; Android cloud backup leaves `attachments/` out, because of its 25 MB limit.
**2026-11-07** — Assumed (build): a shortcut's files go through `shortcuts-inbox/<id>/`, and a note from the inbox keeps the shortcut's id, so a late note is not kept twice and gets no place, because it was made before the app opened.
**2026-11-07** — Assumed (build): *Add a note* with no words and no files asks *What do you want to keep?* instead of failing; the screenshot recipe uses Back Tap with *Take Screenshot*, because iOS has no "when I take a screenshot" trigger.
**2026-11-07** — Assumed (build): no `schema/seed.sql` rows, because notes and files live in each person's space, which the D1 seed does not reach.
**2026-11-07** — Assumed: a note with files that the server refuses with 400 goes once more without its `attachments` list, because a server from before this change refuses the unknown field, and the phone would otherwise drop the note and mark it sent.
**2026-11-07** — Assumed: the Android app removes the storage and media read permissions that the file opener adds, because the app opens only its own files and must ask for no access it does not use.
**2026-11-07** — Assumed: Matthew's iPhone check moves from a task to a note after the publish, because the TestFlight build is made only from `main`, so the check can't run before the merge.
**2026-11-07** — Assumed: `mobile/README.md` and `connection.dart` stop naming the deleted `scripts/relay-device-key.mjs`, because a saved note asked the next phone change to fix them, and this is that change.
**2026-11-07** — Built and checked locally: app suite, 141 phone tests, `flutter analyze`, the website build, `public-check` and the name check pass; a second look found six issues, all fixed.
**2026-11-07** — Checked on staging (`app-staging`, branch spaces Worker and server deployed by hand): a phone key sent a note with a picture and a PDF from a script, not the simulator, which can't reach staging. The page's timeline data showed both waiting, then ready; the PDF downloaded with the same bytes; a resend stored once; a device key got 403 and no sign-in 401; the webhook's `note.created` listed both files with no bytes. The trial key and webhook were turned off.
**2026-11-07** — Checked on the iPhone simulator (device check on `cada368`): the app builds with iOS 15.0 as its lowest version, and the Shortcuts app lists *Add a note to Relay Everything* and *Get notes from Relay Everything*. Tapping *Add a note* shows *Unable to run App Shortcut*, so the flow's note never reached the timeline, and the run gave no system log to show why.
**2026-11-07** — Assumed: the iPhone check now keeps the phone's log for the app, Shortcuts and App Intents, and the app's crash reports, because the failed action gave no words on the screen, and the next failure of this kind needs the same evidence.
