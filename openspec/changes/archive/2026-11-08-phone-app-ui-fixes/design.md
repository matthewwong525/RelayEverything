# Design

## Context

See proposal.md for why. Today both ⋯ menus are a bare `MenuAnchor` (`home.dart` `_MoreMenu` and `note_editor.dart` `_MoreMenu`). A `MenuAnchor` opens with its left edge under the anchor's left edge, so a menu from a button near the right edge runs past the screen and Flutter pushes it flush against the edge: the crooked, cut-off *Copy* in the person's screenshot. `MaterialApp` sets `theme` and `darkTheme` and no `themeMode`, so it always follows the phone. `SyncLine` (`timeline.dart`) makes the state itself a hidden tap that calls `relay.sync`. The note page's Quill editor shows a plain-text URL as plain text, and `sendState()` (`days.dart`) is a plain `Text`.

Two open pull requests touch the same files; whichever merges first, the other takes `main` and fits the overlap:

- **#64, note sync** (`explain-data-storage`): pull to refresh on Home and folders calls `relay.pullNotes`, not `relay.sync`, and `SendingPage` (`folder.dart`) gains an `opener` and a *Notes from elsewhere* row.
- **#65** (`stop-tap-visual-feedback`): Home's section headers take a plain tap (`GestureDetector`), with no Material ink. Keep it.

## Goals / Non-Goals

**Goals:** one ⋯ menu that fits; a remembered light/dark pick; Settings in one tap; Sync now in sight; links that open; send a waiting note on a tap; the version in Settings.

**Non-Goals:** deleting a note (change *Delete a note everywhere*), pinning, row long-press menus, haptics, changing the share card's theme.

## Decisions

### One shared ⋯ menu

New `mobile/lib/screens/more_menu.dart` holds `MoreMenu({items, builder})`, items as `(label, icon, onPressed)`, used by `note_editor.dart`; the Home copy goes with Home's ⋯. It wraps `MenuAnchor` with:

- `alignmentOffset` computed in the builder from the anchor's and the menu's width, or `style: MenuStyle(alignment: AlignmentDirectional.bottomEnd)` plus a `crossAxisUnconstrained: false` layout, so the menu's right edge lines up with the button's. Pick whichever passes the 375-point test below; record it in the Decision log.
- `MenuStyle`: `shape: RoundedRectangleBorder(14)`, `backgroundColor: brand.card`, `elevation` a soft shadow, `padding: 6` vertical, and a 12-point inset from the screen edge (`MenuStyle.visualDensity` does not do this; use the `Padding` the overlay allows, or clamp `alignmentOffset`).
- Items keep the icon leading, as the app's menus do today: `CupertinoIcons`, 20 pt, muted.

Alternative: the `pull_down_button` package draws Apple's pull-down menu exactly, but it adds a dependency for two items; a styled `MenuAnchor` is enough.

### Appearance

`Settings` gains `appearance` (`enum Appearance { system, light, dark }`, default `system`, encoded by name; a missing key decodes as `system`). `Relay`/`controller.dart` gain `setAppearance(Appearance)`, saving like `setPinNotes`. `RelayApp` wraps `MaterialApp` in a `ListenableBuilder` on `relay` and sets `themeMode` from it. Settings shows an *Appearance* group first, with a `SegmentedButton<Appearance>` (*System*, *Light*, *Dark*) in brand colors (selected segment `accentSoft`, so *New note* stays the one filled accent).

### Home's gear and the page link

`_bar()` in `home.dart` drops `_MoreMenu` for an `IconButton` with `CupertinoIcons.gear`, tooltip *Settings*, on the same `brand.card` circle. *Open your Relay Everything page* becomes a row on `SendingPage` in `folder.dart`, shown only while sending to a Relay Everything server with a known server, opened through the same opener Home uses. If #64 is on `main` by then, use its `opener`; else add one as #64 does, so the merge takes one.

### Sync now beside the state

`SyncLine` gains `onSync` (required while sending), passed by Home and `TimelineScreen` as the same function their `RefreshIndicator.onRefresh` calls (`relay.sync` today, `relay.pullNotes` after #64). After the state's text it draws a small `IconButton` (`CupertinoIcons.arrow_2_circlepath`, 16 pt, muted, tooltip *Sync now*, 32-pt tap target via `visualDensity`). While `relay.status == SyncStatus.syncing` the icon turns with a `RotationTransition`, still under `MediaQuery.disableAnimationsOf`. The state's own tap stays.

### Links

The page finds web addresses when it draws: a `LinkDetector` pass over the Quill document marks `https?://…` and `www.…` ranges with Quill's link attribute in the shown document only, through `controller.document.format` with `ChangeSource.silent`, before `_saved` is taken, so the opened Delta compares equal and an untouched note is never written back. The Markdown codec already ignores link attributes on write, so detection never reaches the stored words; a test proves it. `QuillEditorConfig.onLaunchUrl` opens the address with `url_launcher` (`LaunchMode.externalApplication`) only while the editor has no focus; with focus, the tap places the cursor (Quill's default with `readOnly: false`). Links draw in `brand.accentText`, underlined, through `customStyles.link`.

If the silent format still marks the document changed, fall back to a `customRecognizerBuilder` or a link `TextSpan` builder; record which in the Decision log.

### Waiting to send

In `_page()` the state line becomes a `TextButton` styled as `quietButton` when `note.waiting`: label *Waiting to send · Send now*, tap calls `relay.sync()` and shows *Sending…* while `relay.status == SyncStatus.syncing`. `Sent` stays plain text.

### Version

Add `package_info_plus` (BSD-3). Settings' last row, muted and centred: *Relay Everything <version> (<buildNumber>)*, read once with `PackageInfo.fromPlatform()` in a `FutureBuilder`. Tests pass `PackageInfo.setMockInitialValues`.

## UX

### Use-case brief

The person, on their iPhone, opens a note to copy or share it, flips the app to dark at night, opens Settings, and checks that a note went. Done is: the menu reads cleanly, the app keeps the look they chose, Settings is one tap, and they can send a waiting note and open a link without leaving the note. Edge: a small 375-point phone, reduced motion, sending off. Model: Apple Notes on iOS 26.

### Flow

Home → gear → Settings → *Appearance: Dark*. Home → *Synced ↻*. Home → Shares → note → ⋯ → Copy. Note → tap link → browser. Note → *Waiting to send · Send now* → *Sent*.

## Risks / Trade-offs

- **Both open PRs edit `home.dart`, `folder.dart` and `timeline.dart`** → keep edits small and local; fit after whichever merges first.
- **Silent link marks could flip "changed"** → covered by a test that opens and leaves a note with a link and checks the outbox and words.
