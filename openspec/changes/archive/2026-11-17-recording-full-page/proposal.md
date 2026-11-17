**Status:** shipping
**Branch:** fix-transcript-open-splash
**Open questions:** none

## Why

When you open a recording's transcript in a note, the words show inside a rounded box, like a form field. A tap on *Transcript* also sends a grey splash across the card. Both look cheap. Apple Notes does this better: a tap on a recording opens it on its own full page, with the words in plain text.

## What Changes

- **In the note, the recording's card shows the player and one *Transcript ›* row, with no words.** A tap on the row opens the recording's page. The tap shows no splash. While the phone writes the words, or when they did not come, the card says so as it does now.
  ```picture
  Before: pictures/before.png
  ```
  ```page
  After, the card in the note: pages/after-note.html
  ```
- **The recording's page shows all the words as plain text, with no box, and the player at the bottom.** The top has the way back to the note and a copy button. The date and the length show under the top. Long words scroll.
  ```page
  After, the recording's page: pages/after-page.html
  ```
- **On the phone's own note, you fix a word by tapping it on the page.** The cursor goes there and the keyboard comes up, with no box. The round check button closes the keyboard, as in the note. The change is kept when you leave the page, as now.
  ```page
  After, fixing a word: pages/after-edit.html
  ```
- **The website's voice notes and notes pages say the same.**

## What the build needs

- **Nothing.**

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-notes-screen`: the recording card no longer folds its transcript open in place; it opens a full page for the recording, with the words and the player.

## Impact

- `mobile/lib/screens/note_blocks.dart`: `RecordingCard` loses its fold; a new recording page holds the words, copy, editing and the player.
- `mobile/test/screens_test.dart`: the transcript tests follow the new page.
- `mobile/device-check/flows/recording-card.yaml`: the open-transcript step opens the page.
- `site/src/content/docs/app/voice-notes.md` and `site/src/content/docs/app/your-notes.md`.
- No server, data or route change.
