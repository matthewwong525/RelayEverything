# The waiting count counts notes, not each file

**Status:** ready-to-ship
**Branch:** waiting-notes-count
**Open questions:** none

## Why

Under the title of Home and of the notes list, the phone says how many notes wait to send. Today it counts each thing in the phone's send queue: a note, and each of its photos, files and recordings, and also batches of health, places and calendar data. Since recordings became files, 3 voice notes show *3 notes · 6 waiting*. The number should be the notes that wait.

## What Changes

- **The waiting count counts each waiting note once.** A note that waits to send counts as 1, with all its photos, files and recordings. A note change, pin, delete or recover that waits also counts its note once. Health, places, calendar and photo data no longer count here: each keeps its own count on its own page, such as *Health*, as today. The state still shows only while sending is on, beside the same dot.
  ```picture
  Before: pictures/before-list.png
  After: pictures/after-list.png
  ```

## What the build needs

- **Nothing.** The change uses only the phone's own send queue.

## Non-goals

- A count of waiting files or data anywhere else.
- Changes to when the state shows, its dot, or how notes send.

## Capabilities

### New Capabilities

### Modified Capabilities
- `relay-brand`: the sync state's number counts waiting notes, each once with its files, and no other data.

## Impact

- Phone: `mobile/lib/data/store.dart` (`waiting()` counts distinct notes in note routes), tests in `mobile/test/store_test.dart` and `data_test.dart`.
- Website: `site/src/content/docs/app/your-notes.md` says what the number counts.
