# Edit notes like Apple Notes, with sleeker icons

**Status:** built; checking on staging and an iPhone
**Branch:** apple-style-notes-editor
**Open questions:** none

## Why

Today a note can't change after you save it: the note page only shows it. You also can't make a heading, a list or a checklist. You want the app to write and edit like Apple Notes, and the icons look heavy next to Apple's thin, round ones.

## What Changes

- **Tap a note to edit it, in place.** The note page and the new-note page become one page, the same as Apple Notes. A tap in the words puts the cursor there and the keyboard comes up. At the top: *‹* back on the left, then a round pill with share and ⋯, and a round ✓ that closes the keyboard. Each change is kept on the phone as you type: no *Save* button. A voice note's words can change too; its recording stays as it was.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹</button><span class="grow"/><button class="btn-ghost">Share</button><button class="btn-ghost">⋯</button><button class="btn-primary">✓</button></div>
    <h3>Small things to buy</h3>
    <h3>At home</h3>
    <div>– Lemons</div>
    <div>– Green tea</div>
    <h3>Drinks</h3>
    <div>– Kefir with honey</div>
    <div class="card row gap"><span>Aa</span><span>☑︎</span><span>📎</span><span class="grow"/><span class="muted">keyboard below</span></div>
  </div>
  ```
- **A tool bar floats above the keyboard while you edit.** It is a round, frosted pill, as in Apple Notes: *Aa* (text styles), checklist, and the paperclip (photo or file). Table, drawing and Apple Intelligence are not in this version.
- **Aa opens the text styles.** A panel slides up in place of the keyboard, as in Apple Notes: *Title*, *Heading*, *Subheading*, *Body*, *Monostyled*; bold, italic, underline, strikethrough; bulleted, dashed and numbered lists; block quote; indent in and out. The first line of a new note starts as a *Title*.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Format</h3><span class="grow"/><button class="btn-ghost">✕</button></div>
    <div class="row gap"><span class="tag">Title</span><span class="tag-outline">Heading</span><span class="tag-outline">Subheading</span><span class="tag-outline">Body</span></div>
    <div class="row gap"><button class="btn-ghost">B</button><button class="btn-ghost">I</button><button class="btn-ghost">U</button><button class="btn-ghost">S</button><span class="grow"/><button class="btn-ghost">Mono</button></div>
    <div class="row gap"><button class="btn-ghost">• list</button><button class="btn-ghost">– list</button><button class="btn-ghost">1. list</button><button class="btn-ghost">❝</button><button class="btn-ghost">⇤</button><button class="btn-ghost">⇥</button></div>
  </div>
  ```
- **Checklists tick in one tap.** A checklist line shows a round circle; a tap ticks it in the accent green, even when you are not editing.
- **A bar at the bottom while you read.** With the keyboard down, the bottom shows a pill with checklist and paperclip, and a round compose button that starts a new note, as in Apple Notes.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹</button><span class="grow"/><button class="btn-ghost">Share</button><button class="btn-ghost">⋯</button></div>
    <h3>Small things to buy</h3>
    <div class="row gap"><span>○</span><span>Honey salt</span></div>
    <div class="row gap"><span>◉</span><span class="muted">Lemons</span></div>
    <div class="row gap"><span class="card row gap"><span>☑︎</span><span>📎</span></span><span class="grow"/><button class="btn-primary">✎</button></div>
  </div>
  ```
- **A change to a sent note goes to your Relay Everything page too.** Your page and Claude read the new words, and each of your webhooks gets a *note changed* message. With sending off, the change stays on the phone like any note. With your own webhook picked, the phone sends the *note changed* message there itself.
  ```mermaid
  sequenceDiagram
    participant P as Phone
    participant S as Your Relay Everything page
    participant W as Your webhooks
    P->>P: You edit a sent note
    P->>S: The new words
    S->>W: note changed
  ```
- **Sleeker icons everywhere in the app.** Every icon becomes Apple's thin, round style (back, share, ⋯, compose, paperclip, search, settings, play, mic), in place of today's heavier Android-style ones. This also changes the notes list and Settings.
- **Formatting stays readable outside the app.** The words keep their styles as plain marks such as `#` and `- [ ]`, so Claude, your page and your webhooks read them as normal text. The notes list shows the first line without those marks.

Non-goals: tables, drawing on a note, Apple Intelligence tools, pinning, folders, and deleting a note.

## What the build needs

- **Nothing.** The editor and the icons come from free, open packages; the server change uses what the app already has.

## Capabilities

### New Capabilities
- `relay-note-editing`: editing a note in place with Apple Notes styles, the tool bars, checklists, saving each change, sending a change to a sent note, and the icon style.

### Modified Capabilities
- `relay-notes-screen`: the note page edits the note instead of only showing it; the list shows the first line without style marks.
- `relay-webhooks`: the server sends `note.updated` again, for a note changed on the phone.

## Impact

- `mobile/lib/screens/note.dart` and `compose.dart` merge into one editor page; new editor and tool bar widgets; `timeline.dart`, `settings.dart`, `connect.dart`, `hold_to_talk.dart`, `back_to_notes.dart` swap Material icons for `CupertinoIcons`.
- `mobile/lib/data/store.dart`, `outbox.dart`, `sender.dart`, `webhook.dart`: an edited note marks itself to send again, as an update.
- New dependencies: `flutter_quill` (the editor) and `share_plus`, both open licenses.
- Space migration `0010_note_edits.sql` adds `relay_notes.edited_at`.
- Server: a new `PATCH notes` route for phone keys, with the note's client id in the body, in `app/worker/apps/relay/`, logging `note.updated` to the outbox; `npm run relay:api-doc`.
- Website: `site/src/content/docs/app/your-notes.md` and the webhooks page say notes can change and `note.updated` is sent; `site/public/webhooks/v1.schema.json` drops *no longer sent*.

## Decision log

- **2026-11-08** — Asked what happens when you change a note already sent → chose: send the change, so the page and Claude get the new words and webhooks get `note.updated`.
- **2026-11-08** — Asked which Apple Notes tools the first version has → chose: text styles, lists, checklist and attach; tables and drawing later.
- **2026-11-08** — Assumed: the styles are kept as Markdown in the note's text, because the server, Claude and webhooks already read plain text, and the words need no new field.
- **2026-11-08** — Assumed: the ✓ button and ticked checklist circles use the brand accent green, not Apple's yellow, because the brand keeps one color for the main action.
- **2026-11-08** — Assumed: icons come from `CupertinoIcons`, already in the app, because Apple's SF Symbols may not ship on Android under their license.
- **2026-11-08** — Assumed: changes save on each pause in typing, with no *Save* button, because Apple Notes works that way.
- **2026-11-08** — Assumed: the round compose button on the reading bar replaces nothing on the list, which keeps its own *New note* button and hold-to-talk.
- **2026-11-08** — Assumed: no prototype pictures, because the phone app is Flutter and this computer has no Flutter to run it; the sketches stand in.
- **2026-11-08** — Assumed: the route is `PATCH notes` with `clientId` in the body, not `PATCH notes/{clientId}`, because the server's router matches exact paths.
- **2026-11-08** — Assumed: a 404 or 400 for a change drops it, not keeps it waiting, because the phone sends its uploads in order and one stuck change would hold back every note behind it.
- **2026-11-08** — Assumed: no `markdown` package; the codec reads its few marks itself, because it must give back each note byte for byte, and the list preview is `plainText()`, not `plainPreview()`.
- **2026-11-08** — Assumed: typing keeps the words on each pause with no send, and leaving, ✓ or a tick while reading sends them, so a long edit makes one change upload, not one per pause.
- **2026-11-08** — Assumed: adding a file to an unchanged old note keeps its words as they were, so its first line gains `# ` only when the person changes the words.
- **2026-11-08** — Assumed: the codec lives in `mobile/lib/editor/`, not `mobile/lib/notes/`, because the public check refuses any `notes/` folder as a private note.
- **2026-11-08** — Check: `note_editor.dart` ignores `experimental_member_use` for `customLeadingBlockBuilder`, because it is the only way to draw round checklist circles and dashed lists; `pubspec.lock` pins the version.
- **2026-11-08** — Assumed: italic on part of a word is written with `*` (`*foo*bar`) when a `_` would touch a letter, and with `_` otherwise; the reader takes `*…*` italic only when it touches a letter, so `snake_case`, `5 * 3`, an old `*word*` and a `* ` bullet stay as typed.
- **2026-11-08** — Assumed: two code blocks that touch get one empty line between them, so they stay two blocks after an edit; the note then keeps that line.
- **2026-11-08** — Assumed: in own-webhook mode a note's `created_at` is when the phone kept the note, in `note.created` and `note.updated` alike, because the phone keeps no time it first queued the note.
- **2026-11-08** — Asked whether the device-keys rule in `AGENTS.md` should say a phone key can change its own notes → chose: yes, it only adds data, and a phone changes only the notes it sent.
- **2026-11-08** — Asked what happens when you delete every word in a note and leave → chose: delete it from the phone, as Apple Notes does; a note already sent keeps its last words on the page, because the page can't delete notes yet.
- **2026-11-08** — Assumed: a `*` between letters in an old note, such as `2*3*4`, reads as italic, because Markdown reads it the same way and the stored words don't change unless the person edits the note.
- **2026-11-08** — Assumed: an empty note is deleted when you leave its page, not on ✓, as Apple Notes does, because deleting on ✓ and typing again would send a sent note's new words under an id the server already has.
- **2026-11-08** — Saved for final acceptance: built and reviewed in two rounds, local checks pass; the staging check (7.2) and the iPhone device check (7.3) run on the saved commit.
- **2026-11-08** — Assumed: *Aa* takes the cursor away while its panel is open, not keeps it with the keyboard hidden, because on the iPhone check the editor brought the keyboard back each time it was hidden and the tap hung.
- **2026-11-08** — Assumed: renumbered to 0010 because email notes and photos took 0008 and 0009 first; a staging space that ran it as `0008_note_edits` skips it by that name.
- **2026-11-08** — Asked what to do when the iPhone check showed editing, ✓ and the reading bar working but froze before *Aa* → chose: find why taps into the note's words freeze the test tool, fix it, and run the check once more.
