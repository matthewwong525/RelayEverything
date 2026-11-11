# Tasks

## 1. One notes list with filters (phone)

- [x] 1.1 In `mobile/lib/screens/days.dart`, make `NotesFolder` `all('All')`, `voice('Voice')`, `files('Photos and files')`, with `files` as notes with a file and no link test; update `days_test.dart` so a photo or a file shows in `files` and a link alone does not
- [x] 1.2 In `home.dart`, show one *Notes* row with the count of all notes; in `timeline.dart`, add `NoteFilters` with counts, keep the picked filter in the list's state, scope search to it, and set the empty text for *Photos and files*; update `screens_test.dart` and `narrow_test.dart` for one row, the filters, and a photo that does not move a note
- [x] 1.3 In `timeline.dart`, draw two-line rows with no `BrandTag`: the time, a microphone and the length for a voice note, the start of the words, and *Waiting to send* only on a note that waits; test that a sent row says nothing and a waiting row says *Waiting to send*

## 2. Quiet sync state, no sync buttons (phone)

- [x] 2.1 Give `SyncLine` a `stateOf(relay)` that is null when all is sent, when sending is off, or while it syncs with nothing waiting; drop `_SyncNow`; leave out Home's app bar `bottom` while it is null; replace the *Sync now* tests with tests that Home shows no line when all is sent, *1 waiting* with a still dot under reduced motion, and that a pull still syncs
- [x] 2.2 Add `TitleBar` and `_SmallLine` to `timeline.dart` and use them on Home and the list in place of `SliverAppBar.large` with `SyncLine` in `bottom:`; test that scrolled, the top is one row with *12 notes* under the small title, *3 waiting* in its place while notes wait, and on Home no line while all is sent
- [x] 2.3 In `note_editor.dart`, show the date alone at the top and drop `_SendNow` and the bottom tag row; make `SyncLine`'s state words only, not a tap target; test that a waiting and a sent note's page show only the date, with no tag and no send item in ⋯
- [x] 2.4 In `controller.dart`, call `sync()` when `connectivity_plus` reports a connection after none, while notes wait and sending is on; test with a fake connectivity stream that a waiting note sends with no tap, and that nothing leaves with sending off

## 3. Voice player with sound waves (phone and browser)

- [x] 3.1 Add `playback`, `pause()`, `seek()` and `waveOf()` to `Relay` with empty defaults; implement them in the phone's controller and `PhonePlayer` from the `AudioPlayer`'s position and state, and `waveOf` from the WAV's 16-bit samples in 48 RMS bars through `compute`; unit test `waveOf` on a fixture WAV, an `.m4a`, and a silent file
- [x] 3.2 Add `VoicePlayer` and `WavePainter` to `note_blocks.dart`, replacing `PlayRow`: play and pause, the played part in accent text, tap and drag to seek, *0:12 / 0:42* while it plays and the length when stopped, and a plain line with no waves; put it under the date in `note_editor.dart` and drop *Play* from ⋯; test play, pause, seek by tap, and the plain line
- [x] 3.3 In `web/web_relay.dart`, give the browser's `AudioPlayer` the same `playback`, `pause()` and `seek()`; in `web/shell.dart`, show one *Notes* row and the filters in the list column; update `web_shell_test.dart` for one row, the filters and the player's plain line
- [x] 3.4 Update `shortcuts_test.dart` so a recorded shortcut note shows the player, not *Play*

## 4. Smaller looks (phone)

- [x] 4.1 Open the paperclip's *Photos* and *Files* in a `MoreMenu` beside the button, not a bottom sheet, and make the focused search field keep the card color with no green border; test that the paperclip opens a menu with both items

## 5. Docs, brand and the tour step

- [x] 5.1 Add one sentence for the scrolled row to the *Notes* bullet of `mobile/README.md`. Update `site/src/content/docs/app/your-notes.md`, `voice-notes.md`, `on-a-computer.md`, `shortcuts.md` and `settings.md` for one list with filters, the player, the quiet status, and notes that send by themselves with no *Sync now* or *Send now*; check with `node scripts/product-name.test.mjs`
- [x] 5.2 Update `wiki/brand.md`: the *One bright thing* rule without the *Voice* and *Typed* tags (a voice row's microphone is accent text), and the *Words with every color* rule with no *Synced* or *On this phone*; update `brand_test.dart` if it reads the tag colors
- [ ] 5.3 Write `mobile/device-check/flows/notes-filters.yaml`: open *Notes*, tap *Voice* and *Photos and files* and back to *All*, write a note, and see its row; run it in the simulator if Maestro is here, else name it with `--flows notes-filters` in the device check

## 6. Checks

- [x] 6.1 Run `flutter analyze` and `flutter test` in `mobile/`, `node scripts/public-check.mjs` and `node scripts/product-name.test.mjs`, and fix what fails
- [x] 6.2 Draw the built Home, notes list (at the top and scrolled) and voice note with the plan's picture test, and compare them with the plan's After pictures through `preview-review.mjs --approved`
- [ ] 6.3 `/save`, then run the device check on the saved commit with this change's scenarios and `--flows notes-filters`, and report its result
