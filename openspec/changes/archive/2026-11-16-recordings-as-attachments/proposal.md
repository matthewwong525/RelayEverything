# Recordings go in a note like files, each with its own transcript

**Status:** ready-to-ship
**Branch:** audio-note-transcript-layout
**Open questions:** none

## Why

Today a voice note's spoken words become the note's own text. So you can't add your own notes to a voice note without mixing them into the words you said, and a note can hold only one recording. You want a recording to sit in a note like a file, with its transcript as an extra you can open, and your own notes apart from it.

## What Changes

- **A recording is a card at the top of the note, with its transcript folded under it.** The card has play, the sound waves and the length, then a *Transcript* row that shows the first 2 lines. A tap on the row opens all the words, with a copy button; a second tap folds them again. You can correct a wrong word in the open transcript. Your own notes go under the card, in the note, as in any note: the page says *Add notes…* until you type.
  ```picture
  Before: pictures/before-page.png
  After, folded: pictures/after-new.png
  After, open: pictures/after-open.png
  ```

- **A note can hold several recordings, added like a photo.** A new mic button in the note's bottom bar records into the note you have open, on the same full-screen recording screen as a held *New note*. The new recording goes at the bottom of the note, after your words, with the photos and files, in the order you added them. Only the recording a voice note starts with sits at the top. While the phone writes a new recording's words, its card says *Writing the words…*.
  ```picture
  After, a voice note with notes and a second recording: pictures/after-notes.png
  After, the second recording writing its words: pictures/after-writing.png
  After, a typed note with a recording added: pictures/after-typed.png
  ```

- **The notes list shows your own words first.** A row shows your typed words when the note has some, else the start of the first transcript. The microphone and the length stay. *Voice* shows every note with a recording. Search finds words in transcripts too.
  ```picture
  Before: pictures/before-list.png
  After: pictures/after-list.png
  ```

- **A recording goes to your space like a file.** While sending is on, the sound of each recording goes to your own space, sealed, as a photo or a PDF does. The words go with it as its transcript, not in the note's text. You can then play the recording on the Relay Everything web page and in the Mac app. The Mac and the web page still record nothing. The website's privacy page and voice notes page change: they say today that your voice never leaves the phone. The App Store's privacy answers add *Audio Data* too: Apple can refuse an app whose answers miss data it sends. You add it in App Store Connect before the next release.
  ```mermaid
  sequenceDiagram
    participant P as Phone
    participant S as Your space
    participant W as Webhooks, AI
    P->>P: record, write words
    P->>S: note, sound, transcript
    S->>W: text and transcripts
  ```

- **AI apps and webhooks get the transcript on its own.** A note's text holds only what you typed. Each recording in the note's file list carries its transcript and its length. AI apps read the transcript, never the sound. A webhook gets the sound as it gets any file. A webhook that read a voice note's words from the note's text must read the recording's transcript now. This is the same when you are signed in and your space sends to your webhooks, and when you have no account and the phone sends straight to your own webhook.

- **Your voice notes move to the new shape.** On the first open after the update, each voice note's words become the transcript of its recording, and its own text is empty. Recordings from Shortcuts and the Apple Watch work the same way: words you gave with a recording become your notes, and the spoken words become its transcript. With sending on, the recordings of your earlier voice notes go to your space too. This can't be undone.

## What the build needs

- **Nothing.** The build uses the phone's own speech model, the server's file storage and parts that exist now. It needs no new service or key.

## Non-goals

- Deleting one recording from a note. Today no file can be taken out of a note; that waits for a change that removes files.
- Recording on the Mac or on the web page.
- A recording placed between your lines, as Apple Notes can. A recording goes at the bottom with the files, as a photo does; only a voice note's own recording sits at the top.
- A smaller sound file. The phone keeps its recordings as it does now, about 2 MB a minute, under the 25 MB a file may be.

## Capabilities

### New Capabilities

### Modified Capabilities
- `relay-voice-notes`: the spoken words become the recording's transcript, not the note's text; the recording goes to the person's space like a file; a mic in any note adds a recording; old voice notes move to the new shape.
- `relay-notes-screen`: recording cards with a folded transcript at the top of a note's page; a row's title and search read transcripts.
- `relay-note-editing`: the bottom bar and the floating tool bar get a mic button.
- `relay-attachments`: a recording counts as one of a note's files and carries its transcript and length; webhooks name both.
- `relay-shortcuts`: words given with a recording become the note's text, and the spoken words its transcript.
- `relay-note-sync`: a synced phone gets each recording with its transcript, and downloads the sound when the person plays it.
- `relay-web-app`: a recording plays from the person's space, with its transcript.
- `relay-mac-app`: a recording plays from the person's space, with its transcript; the Mac still records nothing.

## Impact

- Phone: `mobile/lib/data/store.dart` (recording fields on `Attachment`, a store step that moves each voice note), `mobile/lib/controller.dart` (keep, write words and send per recording), `mobile/lib/relay.dart` (`Entry.recordings`), `mobile/lib/screens/note_blocks.dart` (`RecordingCard`), `note_editor.dart`, `note_bars.dart`, `timeline.dart`, `days.dart`, `mobile/lib/data/api.dart`, `webhook.dart`, `note_sync.dart`, `mobile/lib/shortcuts/`, `mobile/lib/voice/`, the web and Mac shells.
- Server: a new space migration (`relay_attachments.transcript`, `length_ms`, and a change trigger), `edit-note.ts` (a transcript change), `add-note.ts`, `queries.ts` (files with transcripts; search reads them), `note-sync.ts`, `webhooks/format.ts`, `relay-mcp/tools.ts`, `api-doc.ts`; `npm run relay:api-doc`.
- Website: `site/src/content/docs/privacy.md`, `app/voice-notes.md`, `app/your-notes.md`, `app/on-a-computer.md`, the webhooks page and `site/public/webhooks/v1.schema.json`.
- App Store: `mobile/ios/fastlane/app_privacy_details.json` (on main since PR #136) gets `AUDIO_DATA`; the person adds *Audio Data* in App Store Connect by hand.
- Overlap: the *Apple-style note toolbar* chat plans a new bottom bar for the note, where this change adds *Record*; whichever publishes second takes the other's lines.
- Overlap: the *Simplify Relay Everything webhooks* chat plans one path per webhook: signed in, phone → server → the person's webhooks; with no account, phone → the person's own webhook. It removes *Only to my own webhook* and a signed-in phone's own webhook. This change's webhook fields (`transcript`, `length_ms`, the sound as a file, an empty `text` for a voice note) go on both remaining paths; whichever publishes second follows the other.
- Overlap: the *Delete like Apple Notes* change edits the same server note files and may also add a space migration; the one that publishes second takes the next migration number.
