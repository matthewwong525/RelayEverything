# Tasks

## 1. Settings and the sending gate (mobile/lib/data)

- [x] 1.1 Start from `relay-app-first-version` on `main`; its 34 tests in `mobile/test/` pass before any edit
- [x] 1.2 Add the settings model (`sending`, `pinNotes`, `health`, `locationHistory`; upgrade keeps `sending` on for an install with a key) and the `Sender` gate; unit tests for defaults, the upgrade rule and the forced-off switches
- [x] 1.3 Add `sentAt` to notes and `destination` to the outbox in `store.dart`; `outbox.dart` enqueues notes only with sending on, not on every save; the timeline reads local notes and merges server notes when sending is on; unit tests for enqueue, merge and dedupe by `clientId`

## 2. Turning sending on and off (mobile/lib)

- [x] 2.1 Build the earlier-notes prompt (count, *Send them* enqueues oldest first, *Only new notes* enqueues none and asks again next time) and the connect-first path; unit and widget tests
- [x] 2.2 Build the stop prompt: cancel background jobs and the location stream, delete waiting health and location rows, keep notes and the key; unit and widget tests
- [x] 2.3 In `lib/sync/`, start background health and the location-history recorder only while sending and their switch are on, not on the switch alone; ask permissions at the switch; unit tests that nothing reads or stores while off

## 3. Screens and text

- [x] 3.1 Update Settings (sending switch with its line, dependent switches disabled while off, *Pin notes to where I am*) and the timeline header chip and *Pinned* label with no place lookup while off; widget tests for both states
- [x] 3.2 In `lib/app.dart`, open on the timeline whether or not a key is kept, and reach `ConnectScreen` only from the sending switch; move *Disconnect this phone* and the server address inside the sending section; widget tests for first open with no key and for *Disconnect*
- [x] 3.3 Update the site's *Set up a phone* dialog text in `app/src/apps/relay/` and its test, `mobile/README.md` and `AGENTS.md`'s Relay section
- [x] 3.4 Update the public website pages in `site/src/content/docs/` (`index.mdx`, `start/connect-a-phone.md`, `app/settings.md`, `app/your-notes.md`, `privacy.md`) for offline by default; the website's own tests and privacy check pass

## 4. Verification

- [ ] 4.1 Run the fail-on-any-call test across every screen and job with sending off, `flutter analyze`, `flutter test` in `mobile/`, and the local checks
- [ ] 4.2 `/save`, then on the Android phone with a fresh install in airplane mode: write and pin notes, open Settings, and see no permission asks for health or background location
- [ ] 4.3 On the Android phone against the preview: turn sending on, pick *Only new notes*, then turn off and on and pick *Send them*; see the right notes on the site page, and see health stop after *Stop sending*
- [ ] 4.4 Repeat 4.2 on the iPhone through the next TestFlight build, once the first version's TestFlight step is unblocked
