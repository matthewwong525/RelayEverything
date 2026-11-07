# Tasks

## 1. The theme

- [x] 1.1 In `mobile/lib/brand.dart`, set `bodyMedium` to 16, give `ListTileThemeData` a 13 px muted subtitle and 16 px title, set `cardTheme.margin` to zero, `dialogTheme` to 16 px corners, and the large app bar's title to 32 px 700 on paper; verify `flutter analyze` passes.

## 2. The notes list

- [x] 2.1 Add `mobile/lib/screens/days.dart` with `dayGroup(at, now)` and `entryMatches(entry, query)` as design.md says, and `mobile/test/days_test.dart` for each bucket edge (midnight, 7 and 30 days, month, earlier year) and for matches in words, place and file names, any case; verify `flutter test` passes.
- [x] 2.2 Rebuild `mobile/lib/screens/timeline.dart` as the large-title list: the mark, the ⋯ `MenuAnchor` (*Settings*, *Sync now*, *Open your Relay Everything page* by sending state), `_CountLine` with `_SyncDot`, `ModelCard`, `_DayGroup`s of `_NoteRow`s, the empty state, and pull to sync; remove `_PageCard`, `_SyncChip`, `_LocalChip` and the gear.
- [x] 2.3 Add the bottom dock: `_SearchField` with live filtering, *Cancel*, and the no-match line; `NewNoteButton` beside it.
- [x] 2.4 Add `mobile/lib/screens/note.dart`, the read-only note page (words, pictures, files, *Play*, tag and send state), opened by a row's tap.

## 3. New note: tap to write, hold to talk

- [x] 3.1 In `mobile/lib/screens/hold_to_talk.dart`, replace `HoldToTalkButton` with `NewNoteButton` (tap under 500 ms pushes `ComposeScreen`; at 500 ms a haptic, the mic look, and `startVoiceNote` or `askForModel`; lifting keeps recording) and its screen-reader action *Record a voice note*.
- [x] 3.2 Replace `ListeningCard` and `RecordingSheet` with `ListeningOverlay` (tap anywhere saves, *Cancel* keeps nothing, the clock and the spark *Listening* tag, the screen-reader save label), and make `recordFromShortcut` open it.
- [x] 3.3 Make `ComposeScreen` the plain page: *Save* at the top right, no field border, the first line bold through a styling controller, and the paperclip in a bottom toolbar.

## 4. Settings and the other screens

- [x] 4.1 In `mobile/lib/screens/settings.dart`, use the large *Settings* title, add `_Group` and put the rows in *Notes*, *Voice notes* and *Sending* with no `Divider`; shorten the off help lines and the *Health* title by the table in design.md, add the shared off line, and show *Disconnect this phone* in danger text.
- [x] 4.2 In `connect.dart`, swap the `Divider` for space and a muted *Or*.

## 5. Tests for the app

- [x] 5.1 In `mobile/test/screens_test.dart`: notes grouped under *Today* and *Yesterday*; *New note* the only accent-filled control; search filters and *Cancel* restores; the ⋯ menu's items with sending off, on to a server, and on to a webhook, and *Open your Relay Everything page* calls the opener; a row opens the note page and *Play* plays; the *Syncing* dot animates, the *Synced* dot does not, and with `disableAnimations` the *Syncing* dot does not; the empty state's words; Settings' three headings, no `Divider`, and the shared off line.
- [x] 5.2 Move the voice tests in `screens_test.dart` and `offline_test.dart` from *Hold to talk* to *New note*: a tap under 0.5 s opens the page and records nothing; a 0.5 s hold starts recording, a lift keeps it, a tap anywhere saves; *Cancel* keeps nothing; no model asks first; the screen-reader action records once; Shortcuts opens the same card. Replace the slide-off test with the *Cancel* test, and log any dropped test as a `Check:` line.
- [x] 5.3 Update `narrow_test.dart` for the large title and *Health*; verify `flutter analyze` and `flutter test` pass.

## 6. The iPhone share sheet

- [x] 6.1 Add `mobile/ios/ShareExtension/Brand.swift` with each brand token as a light and dark `UIColor` and Inter's roles; restyle `ShareCardView` with it (paper background, 16 px card fills, filled accent *Save*, Inter).
- [x] 6.2 Add `InterVariable.ttf` and `OFL.txt` to the ShareExtension target's resources in `project.pbxproj`, and `UIAppFonts` to `mobile/ios/ShareExtension/Info.plist`.
- [x] 6.3 In `mobile/test/brand_test.dart`, add a test that reads `Brand.swift` and fails, naming the token, when a light or dark hex differs from `BrandColors`; verify it passes, and fails when one Swift value is changed.

## 7. Device check, docs and website

- [x] 7.1 Update `mobile/device-check/flows/timeline.yaml`, `new-note.yaml`, `share-link.yaml` and `shortcut-note.yaml` for *New note* as a round button labelled *New note*, *Search*, and the listening card's tap to save.
- [x] 7.2 Update `mobile/README.md`'s feature list, and `wiki/brand.md`: `Brand.swift` as the colors' fourth home, no line about Material's 14 px sizes, *New note* as a round button, and the sync dot under *Words with every color*.
- [x] 7.3 Update `site/src/content/docs/app/your-notes.md` (the list, groups, search, ⋯ menu, note page, sync state), `voice-notes.md` (hold *New note*, let go, tap anywhere), `shortcuts.md` (tap anywhere to save), `settings.md` (the groups, *Health*, the ⋯ menu in place of the gear) and `share.md` (the iPhone sheet's look); verify `node scripts/product-name.test.mjs` passes.

## 8. Checks

- [x] 8.1 Run `flutter analyze` and `flutter test` in `mobile/`, `node scripts/public-check.mjs`, and the wiki link check; verify all pass.
- [ ] 8.2 `/save`, then run the iPhone device check with this change's scenarios, including a hold on *New note*, a search, and a share into Relay Everything in dark mode; verify its pictures match the drawing in light and dark, and show them beside the drawing on the preview page.

## 9. Review fixes

- [x] 9.1 Keep the first line bold while the keyboard composes a word: `_FirstLineBold` splits the composing underline across the bold line and the rest, with tests for a word in the first line and a range across the line break.
- [x] 9.2 Keep the listening card usable when the recorder fails: the controller clears `listening` and deletes the file when the microphone's stop or cancel throws, the card resets after a failed save and *Cancel* always runs, with a test where stop throws and *Cancel* still closes the card and keeps nothing.
- [x] 9.3 Make `connect-a-phone.md` use the connect screen's words: the muted *Or*, then *Use a key from Add a device on your Relay Everything page*.
- [x] 9.4 Say plainly when the phone cannot keep a voice note: the controller catches a failed `addVoiceNote`, deletes the recording and returns *The voice note did not save.*, and the card's guard offers a retry only while it still listens; with a controller test where `addVoiceNote` throws and nothing is kept.
