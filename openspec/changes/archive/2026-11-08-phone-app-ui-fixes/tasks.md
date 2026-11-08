# Tasks

## 1. The ⋯ menu and Home's gear (phone)

- [x] 1.1 Write `mobile/lib/screens/more_menu.dart`: one `MoreMenu` with the right edge lined up under its button, a 12-point screen margin, round corners and brand card colors. Use it in `note_editor.dart` and remove both `_MoreMenu` copies.
- [x] 1.2 In `home.dart`, replace Home's ⋯ with a gear button (`CupertinoIcons.gear`, tooltip *Settings*) that opens Settings. Keep #65's plain-tap headers if they are on `main`.
- [x] 1.3 In `folder.dart`, add *Open your Relay Everything page* to `SendingPage`, shown only while sending to a Relay Everything server, through an opener (#64's, if on `main`).
- [x] 1.4 Widget tests: at 375 × 812 the note's ⋯ menu lies fully on screen with its right edge in line with the button's (±1 pt); the gear opens Settings in one tap; Home has no ⋯; the page row shows on Sending only in server mode and opens the page.

## 2. Sync now (phone)

- [x] 2.1 `SyncLine` takes `onSync`, the same function as the page's pull to refresh, and draws a muted ↻ button after the state while sending is on; it turns while syncing and stays still under reduced motion. Home and `TimelineScreen` pass it.
- [x] 2.2 Widget tests: tap ↻ calls the pull-to-refresh function; no ↻ with sending off; reduced motion keeps it still.

## 3. Appearance and version (phone)

- [x] 3.1 `Settings.appearance` (system, light, dark; old settings read as system), `setAppearance` on `Relay` and the controller, and `RelayApp` sets `themeMode` from it.
- [x] 3.2 Settings: an *Appearance* group first with *System*, *Light*, *Dark*; the version and build at the bottom through `package_info_plus` (add to `pubspec.yaml`).
- [x] 3.3 Tests: encode/decode round trip and the old-settings default; picking *Light* on a dark platform shows light colors and survives a restart; Settings shows the three groups and the version line.

## 4. Note page (phone)

- [x] 4.1 Links: mark web addresses in the shown document only, draw them in the accent and underlined, open them with `url_launcher` on a tap while reading; a tap while editing places the cursor.
- [x] 4.2 *Waiting to send* becomes a quiet button, *Waiting to send · Send now*, that syncs and says *Sending…* while it goes.
- [x] 4.3 Tests: a note with a plain URL opens and leaves with words and outbox unchanged; a tap while reading calls the opener with the address; a tap while editing does not; the waiting button calls sync.

## 5. Website

- [x] 5.1 `site/src/content/docs/app/your-notes.md`: the gear in place of the ⋯ menu section, Sync now beside the state, links open, tap *Waiting to send*; the page link on Sending. `site/src/content/docs/app/settings.md`: *Appearance* and the version line.

## 6. Checks

- [x] 6.1 `flutter analyze` and `flutter test` in `mobile/`; `node scripts/product-name.test.mjs`; `node scripts/public-check.mjs`.
- [x] 6.2 The iPhone device check shows the note's ⋯ menu inside the screen, Settings with *Appearance* in dark and light, and the ↻ beside the sync state.

## 7. Review fixes

- [x] 7.1 An address typed in this visit becomes a link when editing ends (✓, or the keyboard goes down) and after each save: `_markLinks` in `note_editor.dart` marks the shown document as `withLinks` does, keeps an unchanged note unchanged, and does not bring the keyboard back. Widget test: type an `https://` and a `www.` address, tap ✓, tap each address → the opener gets it; the stored words have no link marks.
- [x] 7.2 A tap uses the position's affinity (`linkAtPosition`): the right half of a link's last letter opens it, and the right half of the space before a link does not. Test both edges.
- [x] 7.3 `mobile/README.md`: the gear opens Settings, *Sync now* beside the sync state, *Open your Relay Everything page* on *Sending*, and Settings with *Appearance*, *Notes*, *Voice notes* and the version.
- [x] 7.4 The editing-tap test also checks that the cursor lies inside the address.
- [x] 7.5 Link marks are never stored, so `withLinks` and `_markLinks` take every old link mark away first, then mark each web address again, without a stop at its end. The check for no change compares with that result. Tests: a stop after a typed `https://a.com.` is not linked and a tap opens `https://a.com`; a removed `https://` and a space typed inside a link leave no old mark.
- [x] 7.6 `mobile/README.md`: `lib/screens/` names the Settings gear in place of the ⋯ menu.
- [x] 7.7 The iPhone tour's Settings flow (`mobile/device-check/flows/settings.yaml`) taps the gear by its tooltip, *Settings*, in place of ⋯ then *Settings*, and waits for *Appearance*, because Home also has a *Voice notes* folder.
