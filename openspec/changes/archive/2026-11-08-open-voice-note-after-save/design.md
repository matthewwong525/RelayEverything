# Design: A voice note opens its own page when it saves

## Context

`ListeningOverlay` (`mobile/lib/screens/hold_to_talk.dart`) sits in the root overlay, inserted by `_showListening` in `mobile/lib/screens/home.dart`. A tap calls `Relay.endVoiceNote()`, which returns only a problem string. On success, `_keepVoice` stores a `LocalNote` whose `createdAt` is `recording.startedAt`, which is the same `DateTime` as `Relay.listening` while it records, and it refreshes `entries` before `endVoiceNote` returns. `NoteEditor` (`mobile/lib/screens/note_editor.dart`) finds its live entry by `id` (or `at` and `voice` with no id) and falls back to the entry it was given, so a gone note still shows.

## Decisions

- **The overlay reports the save; the timeline navigates.** `ListeningOverlay` gets a required `onSaved(DateTime at)`. `_save` reads `_relay.listening` before `endVoiceNote()` and calls `onSaved(since)` when the result is `null` and `since` is not null. Home's `_showListening` passes a callback that finds the first `relay.entries` item with `voice` and the same `at` to the millisecond as `since` (the store keeps `createdAt` in milliseconds) and calls `openPage(context, NoteEditor(entry: ..., relay: relay, picker:, sharer:, opener:, back: 'Home'))`. Home's navigator is the root navigator, so the page opens over any page a shortcut found open.
  - *Not chosen:* change `endVoiceNote()` to return the note. It changes the `Relay` interface, its fakes and every caller for a value the overlay already has.
  - *Not chosen:* a stream of saved voice notes on `Relay`. It would also catch the 5-minute auto-stop, which the plan leaves out.
- **`endVoiceNote` returning `null` with no recording.** It returns `null` when nothing was recording (a race with Cancel). The entry lookup then finds nothing, and no page opens.
- **A gone note closes its page.** In `NoteEditor._relayChanged`, when the page opened an existing note (`_stored`) and `relay.entries` has no entry with its id, the page sets `_deleted` (so leaving saves nothing) and pops once with `Navigator.maybePop` in a post-frame callback. A new note not kept yet is not affected. The no-speech path in `_write` drops the note and calls `notice(_noSpeech)`; the timeline's notice listener shows the message as it does now.
  - Check while building: the first frame after the push must find the entry. `_keepVoice` awaits `_refreshLocal()` before it returns, so the entry is in `entries` before `onSaved` runs.

## Risks

- A note whose `at` changes after a sync would also close its page. Sync keeps `createdAt`; check in the controller while building, and match on `at` as the page already does.
