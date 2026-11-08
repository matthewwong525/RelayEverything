# Design

## Context

See proposal.md for why. Today `ComposeScreen` (`mobile/lib/screens/compose.dart`) writes a new note in a plain `TextField` whose first line draws bold, and `NoteScreen` (`note.dart`) shows a note read-only. A note is one plain `text` string in the phone's drift store (`LocalNote`), sent once by `POST notes` and stored in `relay_notes.text`. The server sends no `note.updated` since Pebble went away (`0005_no_pebble.sql`), but webhook format v1 still describes it, and `noteUpdated()` in `app/worker/apps/relay/webhooks/format.ts` still builds it. `setWords` in `store.dart` already rewrites a note's text (for voice words) and can mark it to send.

## Goals / Non-Goals

**Goals:** one editor page for new and old notes; Markdown in the text as the only format; a sent note's change reaches the server and webhooks; one icon set.

**Non-Goals:** tables, drawing, collaborative or server-side edits (the page, API and AI connector still can't change a note), undo history kept after leaving the page, and edits to a note's place or time.

## Decisions

### The editor: `flutter_quill`, with Markdown in and out

`flutter_quill` (MIT) is the most used Flutter rich text editor. It has per-line styles (header 1–3, lists, checked list, code block, quote, indent) and inline bold, italic, underline and strike, and it takes our own tool bar in place of its own. A codec in our code turns Markdown into its Delta and back (`mobile/lib/editor/markdown.dart`), with no parser package: it reads line marks and inline pairs itself. We write the codec ourselves, not `markdown_quill`, because we need exact round trips, dashed vs bulleted lists, and `<u>` for underline.

- Title → `# `, Heading → `## `, Subheading → `### `, Monostyled → a ``` fence, bulleted → `* `, dashed → `- ` (the Delta list value `dashed`, drawn as a dash by the editor's leading builder), numbered → `1. `, checklist → `- [ ] ` / `- [x] `, quote → `> `, indent → two spaces per level, bold `**`, italic `_` (or `*` inside a word, as in `*foo*bar`, where `_` would read as words), strike `~~`, underline `<u>…</u>`. Two code blocks that touch get an empty line between them.
- Dashed lists are a custom line attribute that draws `–` and writes `- `; bulleted draws `•` and writes `* `.
- **A note opened and not changed is never written back.** The page compares the Delta to the one it opened with, so an old note with stray `*` or `#` keeps its exact bytes and is not sent again.
- An old note with no `#` on its first line opens with that line shown as a title (as the list shows it today), but its text gains `# ` only when the person changes the note.

Alternatives: `appflowy_editor` has a Markdown codec built in, but its mobile tool bar and node model are heavier to restyle as Apple's, and its codec drops underline and dashed lists. `super_editor` is still 0.x. A spike (task 1.1) confirms `flutter_quill` builds on Flutter 3.47.9 with iOS and Android; if it fails, `appflowy_editor` with our own codec is the fallback, with no change to the specs.

### One page: `NoteEditor`

`compose.dart` and `note.dart` merge into `mobile/lib/screens/note_editor.dart`, which opens either a new note (keyboard up, first line Title) or an existing one (keyboard down). Files, pictures and *Play* stay as blocks under the words, as today; the paperclip adds files to new and old notes. Voice notes still writing their words show the editor read-only until the words arrive.

- **Saving:** a 1.5 s debounce after the last change keeps the words with no send; leave, ✓, or a change with the keyboard down keeps and sends them. Each calls `store.editNote(clientId, markdown, files)`. An unchanged Delta is never written back. A new note is created on its first save with words or a file; an empty new note is never stored. Blank words of a note with no file or recording are never written; on leave, `store.dropEmptyNote` deletes the note and its waiting `notes` or `note.update` upload, and the server keeps its last words.
- **Ticking a checklist circle** while reading toggles that line in the Delta and saves at once, without focus.

### The tool bars

- **Editing:** a pill floating 8 px above the keyboard (`MediaQuery.viewInsets`), with `BackdropFilter` blur over `brand.card` at 80 %: *Aa*, checklist, paperclip. The top bar: back circle, a pill with share and ⋯, and a round ✓ filled with the accent.
- **Aa** swaps the keyboard for a format sheet the keyboard's height (focus stays, `TextInput` hidden by `readOnly` toggling), with the style row, B/I/U/S, Mono, the three list kinds, quote and indent; ✕ brings the keyboard back.
- **Reading:** a bottom pill with checklist and paperclip and a round compose button; compose opens a new `NoteEditor`.
- Share uses the phone's share sheet with the note's plain words (`share_plus`, BSD). ⋯ holds *Copy* and, when the note has a recording, *Play*.

### Sending a change

- **Phone store:** `LocalNote` gains `editedAt`. `editNote` on a sent note sets `editedAt` and puts one `note.update` item in the outbox, replacing any waiting update for that note, so only the latest words go. A note not yet sent just changes its waiting `notes` item. A `notes` item whose body changed while it was on its way becomes a `note.update` item, as the server has the old words.
- **Relay Everything mode:** a new route `PATCH notes` (phone keys only; the router matches exact paths, so the body names the note: `edit-note.ts`, kept apart from `notes.ts`, which the email-notes work also changes) takes `{ clientId, text, attachments? }`, `attachments` being the whole list. It finds the note by `(device_id, client_id)`, so another device's note is a 404. It updates `text`, sets a new `edited_at` column, adds new files as `POST notes` does, and logs `note.updated` in the outbox. New space migration `0008_note_edits.sql` adds `relay_notes.edited_at`; `relay_outbox` already allows `note.updated` (`0007`). A resend of the same words changes nothing and logs nothing.
- **Webhook format:** `note.updated` gains `edited_at` and the note's `attachments`, both optional, so v1 stays compatible; `v1.schema.json` and the example receiver drop *no longer sent*.
- **Own-webhook mode:** `webhook.dart` signs and sends `note.updated` from the phone, with new files as `note.file` after it.

### Icons

Every `Icons.*` becomes the nearest `CupertinoIcons.*` (already a dependency; MIT; drawn after SF Symbols): `chevron_back`, `square_arrow_up`, `ellipsis`, `square_pencil`, `paperclip`, `checkmark_circle`/`circle`, `textformat`, `list_bullet`, `search`, `gear`, `play_fill`, `mic_fill`, `qrcode_viewfinder`, `arrow_up_right_square`. A test fails on any `Icons.` left in `mobile/lib`.

## UX

### Use-case brief

The person who owns the ring, on their phone, fixes or adds to a note in a few seconds: a typo in a voice note's words, a new item on a shopping checklist, a heading to tidy a long note. Done is when they tap back and the change is there, also on their page. Common: small edits to a recent note, ticking checklist items in a shop. Edge: a long note with styles, editing offline. Mirror Apple Notes' note page on iOS 26, the person's model for the app.

### Flow

List → tap a note → read with the bottom bar → tap the words → edit with the floating bar → ✓ or back. New: list *New note* or the compose button → type → back. Tick: open note → tap a circle.

### Hierarchy

Reading: the words; the one primary action is compose. Editing: the words; the one primary action is ✓ (accent). The tool bar and top pill stay quiet in `card`.

### Review

[review.html](review.html): What Changes items 1 (editing), 3 (Aa sheet) and 5 (reading) sketch the page's three states.

### Components

Reuses `BrandColors`, `BackToNotes` (restyled as a round back button), `_Picture`, `_FileRow`, `_Play` and `checkFiles`. New: `NoteEditor`, `FloatingToolBar`, `FormatSheet`, `ReadingBar`, the Markdown codec, and `RoundIconButton`, one round button for back, ✓ and compose.

## Risks / Trade-offs

- [A Markdown round trip changes the person's text] → the unchanged-Delta rule; codec tests round-trip every style and a corpus of sample notes byte for byte.
- [Two phones edit the same note] → only the sending device can change it, and the last update wins on the server.
- [The format sheet and keyboard swap feels unlike Apple's] → check on a real iPhone in the device check before publishing.
- [The email-notes work changes `notes.ts` and the outbox] → the new route lives in its own file; rebase on main before the migration number is fixed.

## Migration Plan

Space migration `0008` runs on each space's next start; old rows get `edited_at` null. Rollback: the phone build that edits needs the route; an older server answers 404, and the phone drops the update, as a waiting item would hold back every upload behind it.
