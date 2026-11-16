# Design

## Context

See [proposal.md](proposal.md#why). The app reads notes from the server only in the notes part of a round (`_notesPart` in `mobile/lib/controller.dart`), and only when a pull waits (`_pull`). `pullNotes()` sets `_pull` and starts a round; a bare `sync()` does not.

Signing in goes `ConnectScreen` → `RelayController.signIn` (saves the key) → `choosePlace` (may ask *Send your earlier notes too?*) → `startSending`. `startSending` turns sending on and calls `_syncAfter()` → `sync()`: the round sends, but reads nothing.

The only other read near sign-in is the `AppLifecycleListener` `onResume` pull (`lib/web/shell.dart` on the Mac, `lib/main.dart` on the phone). It fires when the sign-in window closes, before the key is saved and sending is on, so `Sender.reader` gives null and the pull ends with no call. The Mac's next read is its 5-minute timer (`macPullEvery`) or the next window focus.

Evidence, 2026-11-16: a throwaway test in `test/note_sync_test.dart` loaded a controller with a saved key and sending off, called `startSending(sendEarlier: false, place: SendPlace.server)`, waited with `settled()`, and found no `GET /apps/relay/api/notes`. The test was removed after.

## Goals / Non-Goals

**Goals:** a pull runs in the first round after sending to the server starts, on every platform that uses `RelayController`.

**Non-Goals:** the web build (`WebRelay`) already pulls after sign-in; the 5-minute Mac timer and focus pulls stay as they are; no server change.

## Decisions

- **Ask for the pull in `startSending`, not in `signIn`.** `signIn` only saves the key; sending turns on later in `startSending`, after the earlier-notes question, and `Sender.reader` needs sending on. A pull asked for in `signIn` would end with no read, as the resume pull does now.
- **Only when the place is the server.** `startSending` also starts sending to the person's own webhook, which has no notes to read; `Sender.reader` is null there, and asking for a pull would only open and end an empty wait.
- **Ask for the pull in the round after the one running.** In `startSending`, when `to == SendPlace.server`, call `pullNotes()` when no round runs, or `running.then((_) => pullNotes())` when one does; a webhook keeps `_syncAfter()`. The pull is asked only once the running round ends, so that round can not end it with no read, such as when the move stops its notes part and `_rounds` breaks. The notes part sends the outbox first, earlier notes included, and reads after, so the device's own notes are on the server before it reads. Alternative: set `_pull` on the running round before `_syncAfter()`; rejected, because a running round whose notes part does not empty ends the pull in its `finally`, and the round after it then reads nothing.
- **`startSending` does not wait for the pull.** It returns as today; notes show page by page through `_refreshLocal`, as on a first pull at open.

## Risks / Trade-offs

- [The pull's round fails, such as offline] → the pull ends with the round, as at open; the next focus, network return or timer reads again.
- [Turning sending back on after a stop also pulls] → wanted: notes from elsewhere left at sign-out, or changed while sending was off, come back at once.

## Decision log

- **2026-11-16** — Asked *Plan a fix that reads your notes as soon as you sign in?* → chose *Plan the fix*.
- **2026-11-16** — Assumed: the fix covers every app that shares `RelayController` (Mac, iPhone, Android), because they share the sign-in path and the same bug.
- **2026-11-16** — Assumed: turning sending back on to the server also pulls, because it uses the same `startSending` and the person wants their notes then too.
- **2026-11-16** — Assumed: the site's *Connect a phone* and *On a computer* pages and `mobile/README.md` get one line each, because the project rule updates the website page with each app change.
- **2026-11-16** — Assumed: the check on a real Mac (sign in with notes in the space, see them in seconds) is a follow-up on the next Mac test build, not a build task, because no Mac is reachable from this computer and the controller test covers the same path.
- **2026-11-16** — Assumed: nine tests in `mobile/test/controller_test.dart` that list each call after sending starts now also expect the one `GET notes`, and `sentNotes()` skips a GET, which has no body. One test name said *reads nothing from the server*; it now says *when the server has no others*. This is the new behavior, not a loosened check: each test keeps its other expectations.
- **2026-11-16** — Review: a pull set on the running round ended unread when that round's notes did not all go, such as a move from the own webhook to the server under a running webhook round. The pull is now asked in the round after it. Also, the sign-in test checks that a `POST notes` happens before it checks the order.
- **2026-11-16** — Archive checkpoint: archived for publishing on branch `fix-mac-notes-sync-sign-in`; the review's reread found nothing left; all `mobile/` tests pass.
