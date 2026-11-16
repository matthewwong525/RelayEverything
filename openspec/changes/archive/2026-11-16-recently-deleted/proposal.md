# Delete like Apple Notes: a Recently Deleted folder, shake to undo, and no toasts

**Status:** ready-to-ship
**Branch:** fix-toast-theme-styling
**Open questions:** none

## Why

The short message at the bottom of the app, such as *Note deleted · Undo* or *Copied.*, is a square bar that is not in the Relay Everything look. It is white in dark mode, and it covers *Search* and *New note*. The app copies Apple Notes, and Apple Notes shows no such bar. A deleted note goes to *Recently Deleted* for 30 days, a shake undoes, and a problem shows as an alert. Today a deleted note is gone for good after 5 seconds, so a missed *Undo* loses it.

## What Changes

- **No more toasts.** The bar at the bottom goes away in every place, on the phone, the web page and the Mac. After a delete, the list shows nothing more. *Copied.* and *Secret copied.* show nothing, as in Apple's apps.
  ```picture
  Before: pictures/before-light.png
  Before, dark: pictures/before-dark.png
  After a swipe: pictures/list.png
  ```

- **A problem shows as an alert, as on an iPhone.** A message such as *The browser did not open*, a note that did not go, or *No speech heard* shows in an alert in the middle of the screen, with *OK*.
  ```picture
  After: pictures/problem.png
  ```

- **A deleted note goes to Recently Deleted for 30 days.** A swipe to the left, or ⋯ → *Delete*, moves the note to *Recently Deleted*. Home shows a *Recently Deleted* row under *Notes*, with its count, only while it holds notes. After 30 days, a note goes for good, with its files and recording. Your other phones, the web page and the Mac see the same *Recently Deleted*. Your AI apps never see a deleted note.
  ```picture
  Home: pictures/home.png
  Recently Deleted: pictures/deleted.png
  ```

- **Recover or delete for good.** In *Recently Deleted*, a swipe to the left offers *Recover* and *Delete*. ⋯ offers *Recover All* and *Delete All*. *Delete* and *Delete All* first ask, because they can't be undone. A tap on a note opens it to read. A tap in its words asks you to recover it first, as Apple Notes does.
  ```picture
  Open a deleted note: pictures/recover.png
  ```

- **Shake to undo.** On an iPhone, a shake after a delete shows *Undo Delete Note* with *Cancel* and *Undo*. *Undo* puts the note back in its place. On the Mac and the web page, ⌘Z (Ctrl+Z on Windows) undoes the last delete when you are not typing in a note. Android has no shake undo: the note waits in *Recently Deleted*.
  ```picture
  After a shake: pictures/shake.png
  ```

- **A note you empty and leave is deleted for good**, as in Apple Notes: it has no words to keep, so it does not go to *Recently Deleted*.

- **The website's *Your notes* page** tells how to delete, recover and undo.

Deleting from *Recently Deleted*, and the 30-day end, can't be undone.

**Non-goals:** a toast in a new look; an *Edit* mode to pick several notes; three-finger swipe to undo; a change to how long notes stay before you delete them.

## What the build needs

- **Nothing.**

## Decision log

- **2026-11-15** — Asked how far to copy Apple Notes for toasts → chose copy Apple fully: no toasts, a *Recently Deleted* folder for 30 days, shake to undo, and problems as alerts.
- **2026-11-15** — Assumed: *Copied.* shows nothing, because Apple's apps show nothing after a copy.
- **2026-11-15** — Assumed: on the Mac and the web page, ⌘Z or Ctrl+Z undoes the last delete, because they have no shake and Apple Notes on the Mac undoes a delete with ⌘Z.
- **2026-11-15** — Assumed: Android gets no shake undo, because Android has no shake undo of its own; *Recently Deleted* keeps the note safe.
- **2026-11-15** — Assumed: webhooks get `note.deleted` when a note moves to *Recently Deleted*, as they do today, and a new `note.recovered` with the whole note when it comes back; nothing more when it goes for good, because a receiver that knows only `note.deleted` must keep working.
- **2026-11-15** — Assumed: Apple's words for the alerts and the folder (*Recently Deleted*, *Undo Delete Note*, *Recently deleted notes can't be edited.*), because the app copies Apple Notes.
- **2026-11-15** — Assumed: one plan for the server, the app and the website, because the folder is the same on every device and must sync.
- **2026-11-16** — Archived and saved for publishing: the phone checks (885 tests), the server's 1269 other tests and its lint, and the public check pass; one test that builds a 25 MB file timed out once on a busy machine and passes alone.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-note-deleting`: a delete moves the note to *Recently Deleted* for 30 days, with recover, delete for good, shake or ⌘Z undo, and `note.recovered`; no 5-second *Undo* bar.
- `relay-brand`: the app shows no toast; a problem shows as an alert.

## Impact

- `app/worker/apps/relay/`: a space migration adds `deleted_at` to `relay_notes`; `DELETE notes` sets it (and `forever: true` removes at once); a new `POST notes/recover`; the change feed carries `deletedAt`; every reader (`queries.ts`, `answers.ts`, `kinds.ts`, `audio.ts`, `relay-memory/store.ts`) leaves out deleted notes; the space alarm removes notes 30 days after `deleted_at`; `note.recovered` webhook kind. `npm run relay:api-doc` rewrites the API and webhook docs.
- `mobile/lib/`: the store keeps `deleted_at`; `Relay` gains `deleted`, `recover`, `deleteForever`, `deleteAll`, `recoverAll`; a new *Recently Deleted* page; Home and the wide shell's left bar get its row; an iPhone shake channel; ⌘Z on Mac and web; every `showSnackBar` becomes `showProblem` (an alert) or nothing.
- `site/src/content/docs/app/your-notes.md` and the webhook docs.
