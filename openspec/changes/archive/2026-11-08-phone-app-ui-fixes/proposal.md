# Phone app fixes: a menu that fits, light or dark, a Settings gear and Sync now in view

**Status:** ready-to-ship
**Branch:** ui-fixes-settings-theme-toggle
**Open questions:** none

## Why

On the note page, the ⋯ menu opens off the right edge of the screen and sits crooked under its button. You can't pick light or dark for the app. On Home, Settings hides in a ⋯ menu, and *Sync now* hides there too, far from the line that says *Synced*. Links in a note don't open, and *Waiting to send* does nothing when you tap it. You also can't see which build you have.

## What Changes

- **The ⋯ menu fits.** Its right edge lines up with the ⋯ button, it stays 12 points in from the edge of the screen, and it has round corners, as on an iPhone. Home and the note page use the same menu.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹ Shares</button><span class="grow"/><button class="btn-ghost">Share</button><button class="btn-ghost">⋯</button></div>
    <div class="row gap"><span class="grow"/><div class="card col gap"><span>⧉ Copy</span><span class="sep"/><span>▶ Play</span></div></div>
    <span class="muted">Yesterday at 6:41 PM</span>
    <h3>Onfido Verification</h3>
  </div>
  ```
- **Pick light or dark.** Settings gets an *Appearance* group with *System*, *Light* and *Dark*. It starts on *System*, which follows the phone as today. The phone remembers your pick.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹ Home</button></div>
    <h3>Settings</h3>
    <span class="muted">Appearance</span>
    <div class="card row gap"><span class="tag">System</span><span class="tag-outline">Light</span><span class="tag-outline">Dark</span></div>
    <span class="muted">Notes</span>
    <div class="card row gap"><span class="grow">Pin notes to where I am</span><span class="tag-outline">Off</span></div>
    <span class="muted">Voice notes</span>
    <div class="card col gap"><span>Speech model</span><span class="muted">On this phone, 142 MB.</span></div>
    <span class="muted">Relay Everything 1.4.0 (91)</span>
  </div>
  ```
- **A gear on Home opens Settings.** The ⋯ on Home becomes a gear. *Open your Relay Everything page* moves to the *Sending* page, where the server already shows.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><span>R</span><span class="grow"/><button class="btn-ghost">⚙</button></div>
    <h3>Home</h3>
    <div class="row gap"><span>● Synced</span><button class="btn-ghost">↻</button></div>
    <div class="card col gap"><span>Notes · 12</span><span>Voice notes · 3</span><span>Shares · 2</span></div>
  </div>
  ```
- **Sync now sits beside the sync state.** A small ↻ button follows *Synced* on Home and in each folder, while sending is on. It turns while the phone syncs. A tap on the state still syncs too.
- **Links in a note open.** A web address in a note shows in green, underlined, and a tap opens it in the phone's browser. This works for an address you typed or pasted as plain text, too. While you edit, a tap puts the cursor in the link, as in Apple Notes.
  ```screen
  <div class="card col gap phone">
    <h3>Onfido Verification</h3>
    <span class="tag-outline">https://id.onfido.com/XX6L46TU ↗</span>
    <span>Hello friend</span>
  </div>
  ```
- **Tap *Waiting to send* to send now.** On a note's page, *Waiting to send* becomes a small button that sends what waits. It says *Sending…* while it goes.
  ```screen
  <div class="card row gap phone"><span class="tag">Typed</span><button class="btn-ghost">Waiting to send · Send now</button></div>
  ```
- **The version at the bottom of Settings**, such as *Relay Everything 1.4.0 (91)*, so you know which TestFlight build you have.
- **The website's phone app pages** say all of this.

Non-goals: deleting a note (its own change, *Delete a note everywhere*), pinning notes, a long-press menu on note rows, and haptics.

## What the build needs

- **Nothing.** The version reader is a free, open package (`package_info_plus`); the browser opener is already in the app.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-home-screen`: Home has a gear for Settings in place of the ⋯ menu; *Sync now* is a button beside the sync state; *Open your Relay Everything page* is on the Sending page; Settings holds *Appearance* and the app version.
- `relay-brand`: light and dark follow the person's pick, *System* by default; Settings' groups are *Appearance*, *Notes* and *Voice notes*; the sync state has a ↻ button that turns only while syncing.
- `relay-note-editing`: the ⋯ menu lines up under its button inside the screen; web addresses in a note show as links and open on a tap; *Waiting to send* sends now on a tap.

## Impact

- `mobile/lib/screens/home.dart`: gear in place of `_MoreMenu`; `mobile/lib/screens/folder.dart`: *Open your Relay Everything page* row on `SendingPage`.
- New `mobile/lib/screens/more_menu.dart`: one shared ⋯ menu (right-aligned `MenuAnchor`, inset from the screen edge, round corners) for `note_editor.dart`; `home.dart`'s copy goes.
- `mobile/lib/screens/timeline.dart`: `SyncLine` gains the ↻ button.
- `mobile/lib/screens/settings.dart`, `mobile/lib/app.dart`, `mobile/lib/data/settings.dart`, `mobile/lib/controller.dart`: *Appearance* saved on the phone and fed to `MaterialApp.themeMode`; version line.
- `mobile/lib/screens/note_editor.dart`: link detection and taps through `url_launcher`; *Waiting to send* button.
- New dependency: `package_info_plus` (BSD-3).
- Website: `site/src/content/docs/app/your-notes.md` and `settings.md`.

## Decision log

- **2026-11-08** — Asked how dark and light mode should work → chose: *System*, *Light* and *Dark* in Settings, starting on *System*.
- **2026-11-08** — Asked which extra ideas go in this change → chose: delete a note, tappable links, tap to send now, and the version in Settings.
- **2026-11-08** — Asked where a deleted sent note should go away → chose: everywhere, the phone, the page and a webhook message.
- **2026-11-08** — Asked whether to split delete-everywhere from the screen fixes → chose: two changes; *Delete a note everywhere* plans in its own workspace after note syncing lands.
- **2026-11-08** — Assumed: Home's ⋯ becomes Apple's thin gear (`CupertinoIcons.gear`), because the person asked for a settings icon and the app uses Apple's icons.
- **2026-11-08** — Assumed: *Open your Relay Everything page* moves to the *Sending* page, because that page already holds the server, and Home's top bar keeps one button.
- **2026-11-08** — Assumed: the ↻ button is muted, not the accent green, because *New note* stays the one bright control on the screen.
- **2026-11-08** — Assumed: a link is found when the note shows, and the note's stored words don't change, so an old note is never sent again only to mark its links.
- **2026-11-08** — Assumed: no prototype pictures, because this computer has no Flutter to run the app; the sketches stand in, and the iPhone device check shows the real screens.
- **2026-11-08** — Assumed: the ⋯ menu opens with `MenuController.open(position:)`, its place worked out from the button's width and place on the screen, and a fixed 220-point width; neither `alignmentOffset` nor `MenuStyle.alignment` knows the menu's width before it opens. Its right edge lines up with the pill the person sees.
- **2026-11-08** — Assumed: links are marked on a throwaway copy of the opened note's Delta (`withLinks`), so no change event or undo step happens, and a tap opens a link through `QuillEditorConfig.onTapUp` while the editor has no focus. Quill itself gives a link only a long press while the page can be edited, so `onLaunchUrl` alone never fires on a tap; the long press menu's *Open* goes through the same opener.
- **2026-11-08** — Assumed: the sync line under the title grows from 28 to 36 points, to give *Sync now* its 32-point tap target.
- **2026-11-08** — Assumed: Home and each folder pass one `_refresh` function to both pull to refresh and *Sync now*. When #64 (note sync) merges, its `onRefresh: relay.pullNotes` line meets `onRefresh: _refresh` in `home.dart` and `timeline.dart`: change `_refresh` to call `relay.pullNotes`. `folder.dart` merges with #64 with no conflict.
- **2026-11-08** — Assumed: an address typed in this visit becomes a link once editing ends (✓ or the keyboard goes down), because the spec promises typed addresses work.
- **2026-11-08** — Assumed: the iPhone tour's Settings flow taps the gear and waits for *Appearance*, because the change removes Home's ⋯ that the flow tapped. Correction to the entry on prototype pictures: this computer has Flutter (`/opt/flutter`), and the build ran `flutter analyze` and 413 tests on it. Saved for final acceptance: built and reviewed in two rounds; the iPhone device check (6.2) runs on the saved commit.
- **2026-11-08** — Assumed: after #64 (note sync) merged, `_refresh` in `home.dart` and `timeline.dart` calls `relay.pullNotes`, so *Sync now*, a tap on the sync state, and pull to refresh all send what waits and then take notes from the person's other devices. *Open your Relay Everything page* sits on *Sending* in the server group, beside #64's rows; #65's plain-tap headers are kept.
- **2026-11-08** — Check: the iPhone device check on 4e5d776 (run 42499289534) gave *works*: the fixed tour passed all four steps, and each scenario showed its THEN: the ⋯ menu under its button inside the screen, the gear opening Settings, *Appearance* with Dark and Light applied at once, the version line, *On this phone* with no ↻ while sending is off, and a typed address shown as a link without the word after it.
