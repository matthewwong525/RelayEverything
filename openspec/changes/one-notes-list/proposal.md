# One notes list, a voice player with sound waves, and no sync buttons

**Status:** in-progress
**Branch:** notes-voice-share-ui-fixes
**Open questions:** none

## Why

The phone app splits the same notes into *Notes*, *Voice notes* and *Shares*, and a note moves to *Shares* when you add a photo. Each row has a *Voice* or *Typed* tag that tells you little. A voice note plays from a small *Play* line at the bottom of its page, with no pause, no progress and no way to skip. Each screen says *Synced* with *Sync now* arrows, each note says *Sent*, and a note that waits has a *Send now* line: a lot of status and buttons for something the app does by itself.

## What Changes

- **One *Notes* list with filters.** Home has one *Notes* row with the count of all notes. The list has three filters at the top: *All*, *Voice*, and *Photos and files*, each with its count. A photo or a file never moves a note: it stays in *All*, and also shows under *Photos and files*. A link alone does not make a note a share.
  ```picture
  Before, Home: pictures/before-home.png
  After, Home: pictures/after-home.png
  ```

- **Rows with no tag.** A row shows the note's title, then its time and the start of its words. A voice note shows a small microphone and its length before the words, in place of the *Voice* tag. A typed note shows no tag.
  ```picture
  Before, the notes list: pictures/before-notes.png
  After, the notes list: pictures/after-notes.png
  After, the Voice filter: pictures/after-voice-filter.png
  ```

- **A voice player at the top, with sound waves.** A voice note's page shows its player under the date: a round play and pause button, the sound waves of the recording, and the time. The part of the waves that has played fills with the green; tap or drag on the waves to go to that point. The time shows *0:12 / 0:42* while it plays, and the length when it stops. *Play* leaves the ⋯ menu and the bottom of the page.
  ```picture
  Before, a voice note: pictures/before-voice-note.png
  After, a voice note: pictures/after-voice-note.png
  ```

- **No sync buttons, and status only when something is wrong.** Notes send by themselves: when the app opens or comes back, when you keep a note, in the hourly background round, and now also as soon as the connection comes back while the app is open. So *Sync now* and *Send now* go, and a note's page shows only its date: no *Sent*, no *Waiting to send*, no tag. When every note is sent, Home shows no status line and the list shows only *6 notes*. A state shows only when notes wait or can't go: *1 waiting* or *Key refused*, and it is words, not a button. With no signal and nothing waiting, no state shows. A note that waits says *Waiting to send* on its row. A pull down on Home or the list still syncs, as a hidden gesture, as in Apple Notes.
  ```picture
  Before, Home: pictures/before-home.png
  After, Home, all sent: pictures/after-home.png
  Before, the bottom of a note: pictures/before-voice-note.png
  After, the list with one note waiting: pictures/after-notes.png
  ```

- **One row at the top when you scroll, as in Apple Notes.** Today *12 notes · Synced* stays as its own band under the top bar while the notes slide under it. After the change, the large title and the line under it go up with the list, and one row stays: *‹ Home*, the small title *Notes*, and one small muted line under it. With every note sent, that line is the count alone, *12 notes*. When notes wait or can't go, the state's words take the place of the count: *○ 3 waiting* or *Key refused*. Home gets the same one row, with no line under *Home* while all is sent.
  ```picture
  Before, scrolled: pictures/before-notes-scrolled.webp
  After, scrolled, all sent: pictures/after-notes-scrolled.png
  After, scrolled, 3 waiting: pictures/after-notes-scrolled-waiting.png
  ```

- **Two smaller fixes.** The paperclip on a note opens a small menu beside it, *Photos* or *Files*, not a sheet from the bottom of the screen. The search field keeps a quiet look while you type, with no thick green border.

- **The browser app matches.** On a computer, the left bar shows one *Notes* row, and the list has the same three filters. A voice note has the same player at the top, with play, pause and seek; it shows a plain line in place of the sound waves, because the browser keeps no copy of the recording to read.

- **The website says the same.** The app pages on relayeverything.com change with the app.
  | Page | What changes |
  |---|---|
  | Your notes | One *Notes* list with three filters; the status shows only when notes wait; no *Sync now* or *Send now*; notes send by themselves; one row at the top when you scroll |
  | Voice notes | The player at the top, its sound waves and seek |
  | On a computer | One *Notes* row and the filters |
  | Shortcuts | A recorded note has the player, not *Play* |
  | Settings | No *Sync now* button beside the state |

Non-goals: hold to paste while you type is a separate change, in its own chat; no change to how notes are kept, sent or synced; no new kind of note.

## What the build needs

- **Nothing.** The recordings are already on the phone, and the sound waves are read from them on the phone. No key, login or new package.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-home-screen`: Home has one *Notes* row; *Sync now* no longer sits beside the sync state, and Home shows no state when all is sent; one row stays at the top of Home and the notes list when they scroll.
- `relay-notes-screen`: one list with *All*, *Voice* and *Photos and files* filters; rows show no tag and say only *Waiting to send*; a voice note's page has a player at the top with sound waves, pause and seek.
- `relay-note-editing`: *Send now* goes; a note's page shows no send state or tag.
- `relay-brand`: the sync state has no arrows and shows only when notes wait or can't go; the list has no spark tag.
- `relay-shortcuts`: a recorded note has the player, not *Play*.
- `relay-note-sync`: no *Sync now* button starts a round; a pull still does; waiting notes send when the connection comes back while the app is open.
- `relay-web-app`: the left bar has one *Notes* row and the list has the same filters.
- `relay-voice-notes`: a note from the Apple Watch shows in the one *Notes* list and its *Voice* filter, and one with no words has the row and the player of any voice note.

## Impact

- Phone app: `mobile/lib/screens/days.dart` (`NotesFolder` becomes the filter: `all`, `voice`, `files`; `files` is notes with a file; the link test goes), `home.dart` (one *Notes* row), `timeline.dart` (`NoteFilters`, two-line rows with no `BrandTag`, `SyncLine` with no `_SyncNow` and no *Synced* or *On this phone*, the quiet search field), `home.dart` (no line while `SyncLine.shows` is false), a shared `TitleBar` in `timeline.dart` for Home and the list (a pinned `SliverAppBar` whose `flexibleSpace` holds the large title and `SyncLine`, and fades in the small title and its line), so `SyncLine` leaves the pinned `bottom:` slot, `note_editor.dart` (the date alone, the player under it, no bottom tag row, no `_SendNow`, no *Play* in ⋯, the paperclip menu), `note_blocks.dart` (`VoicePlayer` and `WavePainter` replace `PlayRow`).
- `mobile/lib/relay.dart` and the phone's relay: `playback`, `pause()`, `seek()` and `waveOf()` beside `play()`; `mobile/lib/voice/recorder.dart` reads the WAV levels and the just_audio position; `mobile/lib/controller.dart` sends waiting notes when `connectivity_plus` says the connection is back.
- Browser app: `mobile/lib/web/shell.dart` (one *Notes* row; the filters in the list column); `mobile/lib/web/web_relay.dart` (`playback`, `pause()` and `seek()` on its `AudioPlayer`; `waveOf()` gives none).
- Tests: `mobile/test/screens_test.dart` and the web shell tests; a new Maestro flow in `mobile/device-check/flows/`.
- Docs: `mobile/README.md` (the *Notes* bullet), `site/src/content/docs/app/your-notes.md`, `voice-notes.md`, `on-a-computer.md`, `shortcuts.md`, `settings.md`; `wiki/brand.md` (the *One bright thing* rule loses the *Voice* and *Typed* tags; the filter chips).
- No data change: the notes and recordings stay as they are.

## Decision log

- **2026-11-11** — Asked how to split notes, voice notes and shares → chose one *Notes* list with filters; a picture never moves a note.
- **2026-11-11** — Asked where the voice player goes → chose the top of the page, under the date.
- **2026-11-11** — Asked how to plan the parts → chose the notes, tags, player and other looks here, and hold to paste in its own new chat.
- **2026-11-11** — Asked where the sent and sync state goes → chose one line under the title: *Synced* stays on Home and the list, a sent note says nothing, and a note that waits says *Waiting to send*, with *Send now* beside the date on its page.
- **2026-11-11** — Asked (in the chat, after the first draft) whether the status, *Sync now* and *Send now* are needed beside the date, or could go in the ⋯ menu → chose status only when something is wrong: no *Synced*, *Syncing* or *On this phone* line, *Send now* in a waiting note's ⋯ menu, and a pull down as the only way to sync by hand. This replaces the one-line-under-the-title answer above.
- **2026-11-11** — Asked (in the chat) whether a *Send now* for each note, or any sync button, is needed → chose to remove both: notes send by themselves, and a pull down stays as a hidden gesture.
- **2026-11-11** — Asked (in another chat, moved here) what stays at the top when the notes list scrolls → chose one row, as in Apple Notes: the way back, the small centered title and one small muted line under it, with no band fixed under the bar; the large title and its line go up with the list.
- **2026-11-11** — Asked (in that chat) what the line says when all is sent → chose the count alone, *12 notes*, with no dot and no *Synced*, under the large and the small title; a problem shows *12 notes · ○ 3 waiting* at the top and the state's words in place of the count when scrolled.
- **2026-11-11** — Assumed: Home gets the same one row, with no line while all is sent, and signed out the notes line is the count alone. That chat assumed *On this phone* on a signed-out Home; this plan shows nothing there, because the app is offline by default and a state shows only when the person can act on it.
- **2026-11-11** — Assumed: *Syncing* alone shows no words in the small line either, only a pulsing dot beside *N waiting*, by the same reason as the large line.
- **2026-11-11** — Assumed: waiting notes also send when the connection comes back while the app is open, through `connectivity_plus`, already in the app, because with no button a note kept offline would otherwise wait until the next open, keep or hourly round.
- **2026-11-11** — Assumed: the state line is words only, not a tap target, because a tap that syncs is a sync button by another name.
- **2026-11-11** — Assumed: this stays in this plan, not the hold-to-paste chat, because it changes the same screens and files.
- **2026-11-11** — Assumed: *Syncing* shows no line of its own, and the dot pulses only beside *N waiting*, because a line that comes and goes on each open makes the title jump.
- **2026-11-11** — Assumed: the filters are *All*, *Voice* and *Photos and files*, and a link alone is not a filter, because a link in a typed note is still a typed note, and that rule is what made notes move.
- **2026-11-11** — Assumed: a voice note's row shows a microphone and its length in the accent text color, not the spark, because the spark is for live moments and a list row is not one.
- **2026-11-11** — Assumed: the sound waves are read from the WAV on the phone each time the page opens, 48 bars, and kept by no one, because a 2-minute 16 kHz recording reads in a few milliseconds and needs no new stored data.
- **2026-11-11** — Assumed: the browser app gets the same player but a plain line where the waves go, because it streams the recording from the server and keeps no copy to read.
- **2026-11-11** — Assumed: the stray *Sign in to Relay Everything* lines at the end of the brand's screen-rules scenario go, because they belong to the Account page rule in `relay-home-screen`, which keeps them.
- **2026-11-11** — Assumed (while building): `Relay.playback` is a `ValueListenable<Playback?>`, and the phone and the browser share one `SoundPlayer` on `just_audio`, in place of the recorder's own player and the browser's `UrlPlayer`, because one player keeps one playback state for every page and test.
- **2026-11-11** — Assumed (while building): a tap or a drag on the waves of a stopped recording starts it from there, as in Voice Memos, because a seek on a player that does not play has no sound to show.
- **2026-11-11** — Assumed (while building): a row no longer shows the place, with the tags gone, because the row is the time, a voice note's microphone and length, the words, and *Waiting to send*; the note's page still shows the place beside the date.
- **2026-11-11** — Assumed (while building): a connection that comes back also syncs after a round that found the phone offline, not only after the phone said it had no network, because the phone can be on Wi-Fi with no internet.
- **2026-11-11** — Assumed (while building): the browser keeps the picked filter in its place, as the sidebar's one *Notes* row opens *All*, and the phone layout in the browser keeps the filter when a note goes back to the list.
- **2026-11-11** — Assumed (while building): a title faded out at the top is not built, so a screen reader and a test read each title once.
- **2026-11-11** — Assumed (while building): the tour's flows that matched *Typed*, *Voice notes* or *On this phone* now match the note's own words, one *Notes* row, and the count alone, because those words are gone.
- **2026-11-11** — Assumed (while building): the plan's test gates between parts moved to the end, as the build writes all source and tests before it runs any.
- **2026-11-11** — Assumed: *Offline* shows no line when no note waits, only *N waiting* when notes wait, because a state shows only when the person has something that can't go (the second look found the plan listed both).
- **2026-11-11** — Assumed (build): in the browser, before a recording first plays, no time shows, because the server gives no length; a tap on the line plays it and then goes to that place once the player knows the length.
- **2026-11-11** — Built: the screens, the player, the quiet sync state and the network send are written with their tests (721 pass); the second look's six findings are fixed; the built screens match the plan's After pictures. Left: the iPhone device check with the new *notes-filters* tour step.
- **2026-11-11** — Assumed (merge with main): a watch note with no words shows *No words heard* in place of its words on the row, after the microphone and its length, with no tag, because main added such notes and this change takes the tags off every row.
- **2026-11-11** — Assumed (merge with main): Home and the browser's left bar keep main's *Other connections* (*Connect your AI*, *Email notes*) under the one *Notes* row, and a row and a note's page show no place, as main took the place off notes.
