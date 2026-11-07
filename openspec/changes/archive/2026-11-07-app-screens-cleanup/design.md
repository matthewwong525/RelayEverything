# Design

## Context

PR #43 gave the app the Emerald colors, Inter and the Signal R through `brandTheme` in `mobile/lib/brand.dart`, but kept every layout, and kept Material's 14 px body size so no screen moved ([`wiki/brand.md`](../../../wiki/brand.md#type)). Today:

- `screens/timeline.dart`: notes are `Card`s with a 12 px pad and Material's 4 px margin; the *Play* button is a `TextButton` in accent text; `_PageCard` is `Card.outlined`; the empty state is one centered line; `_SyncChip` is an `ActionChip` with a Material icon.
- `screens/hold_to_talk.dart`: *Hold to talk* is an `OutlinedButton` with a 1.5 px line and 12 px corners beside a stadium `FloatingActionButton.extended`; it records while held and cancels on a slide off. `RecordingSheet` is the Shortcuts recording, with *Stop* and *Cancel*.
- `screens/settings.dart`: one `ListView` of `SwitchListTile`s with two `Divider`s and long subtitles.
- `mobile/ios/ShareExtension/ShareViewController.swift`: `ShareCardView` in SwiftUI with system colors, `.borderedProminent` *Save*, and 8 px corners.

## Goals / Non-Goals

**Goals:** an Apple Notes layout (large title, day groups, rows, search and *New note* at the bottom, a ⋯ menu, a read-only note page); one *New note* button that writes on a tap and records on a 0.5 s hold that locks; each screen follows the four rules; body text at the brand's 16 px; Settings grouped; a sync dot that pulses only while syncing; the iPhone share sheet in the brand colors and Inter.

**Non-Goals:** editing a saved note; pinned notes or folders; what any switch does, sends or asks; a new note type; a moving logo; the server's Relay Everything page; the Android share card's layout (it gets only the new body size through the theme).

## Decisions

- **Theme first, screens second.** Move `bodyMedium` to 16 and give `ListTileThemeData` a 13 px muted subtitle in `brandTheme`, so every screen gets the brand scale from one place. Remove the line about Material's 14 px from `wiki/brand.md`. Alternative: set sizes per widget; rejected, because a size in a screen drifts from the brand.
- **The notes list, Apple Notes shape.** A `CustomScrollView`: a `SliverAppBar.large` with `RelayMark` at the leading edge, the ⋯ `MenuAnchor` in a round card-filled button at the trailing edge, the title *Notes*, and under it `_CountLine`: *5 notes · ● Synced*. The state part is a button with the tooltip *Sync now*. Then `ModelCard` when the model downloads or failed, then one `_DayGroup` per bucket. `RefreshIndicator` stays for pull to sync.
- **Day buckets.** A pure `dayGroup(DateTime at, DateTime now)` in `mobile/lib/screens/days.dart` returns *Today*, *Yesterday*, *Previous 7 days*, *Previous 30 days*, the month name for this year, or *Month year* for an earlier year; unit-tested at each edge, midnight included.
- **Row.** `_NoteRow` inside the group's `Card`, with a 1 px `line` divider inset 16 px between rows (Apple's look; the brand allows *rare dividers*, and these are inside one card, not boxes in boxes). Line 1: the first line of the words in 16 px 650, or *Writing the words…*, or the first file's name, or *Voice note*. Line 2: the time (today and yesterday `9:41`, this week the weekday, older the short date) in ink 550, then the rest of the words in muted 14 px, one line. Line 3: the kind tag (spark *Voice*, accent-soft *Typed*), then length · place · send state in 13 px muted. A first picture shows as a 48 px thumbnail at the right. The tap opens the note page.
- **The note page.** `screens/note.dart`: back to *Notes*, a centered muted line with the date, time and place, the words in 17 px selectable text, each picture full width with 14 px corners (a tap opens it, as today), each other file as a card row with name and size, *Play* as a quiet card row with the length for a recording, and the kind tag with the send state. It changes nothing.
- **The bottom dock.** A `Positioned` row over the list's bottom, on a paper fade: `_SearchField` (card fill, 24 px radius, 48 px high, a search icon, *Search*) and `NewNoteButton` (52 px round, accent fill, the compose icon, `AccentGlow`). The list gets 110 px of bottom padding so the last row clears it. With the keyboard up, the dock rides above it (`MediaQuery.viewInsets`).
- **Search.** Focusing the field shows *Cancel* in place of *New note*. The list filters live by `entryMatches(entry, query)`: case-insensitive `contains` over the words, the place and each file name, in `days.dart` beside the buckets, unit-tested. The groups stay; empty groups hide. No match shows *No notes with "<text>"*. *Cancel* clears the text, drops focus, and brings back *New note*. Nothing is kept between opens.
- **The ⋯ menu.** *Settings* (the gear's push), *Sync now* (`relay.sync`) while sending, and *Open your Relay Everything page* (the old `_PageCard`'s opener and its *The browser did not open* message) while sending to a server. `_PageCard` and the gear go.
- **Tap or hold *New note*.** `NewNoteButton` keeps a `Listener` as `HoldToTalkButton` does now. Pointer down starts a 500 ms `Timer`. Up before it fires: push `ComposeScreen`. When it fires: `HapticFeedback.mediumImpact`, the button turns spark with a mic, and with the model ready `relay.startVoiceNote()` runs and the listening card opens; with no model, `askForModel` runs and nothing records. Up after it fires does nothing: the recording is locked. A cancelled pointer before 500 ms does nothing. The voice notes rule's 0.5 s floor now sits on this timer, so `startVoiceNote` keeps its own too-short check as a guard.
- **The listening card.** `ListeningOverlay`, shown through an `OverlayEntry` over the whole app: a scrim with a full-screen `GestureDetector` whose tap calls `relay.endVoiceNote()`, and a card above the dock with the spark *Listening* tag, the clock (32 px, tabular figures), a level line in spark, *Tap anywhere to save.*, and *Cancel* (`relay.cancelVoiceNote()`). `recordFromShortcut` opens the same overlay in place of `RecordingSheet`, which goes. Its too-short message stays.
- **Screen readers.** `NewNoteButton`'s `Semantics` label is *New note*, with a custom action *Record a voice note* that does what the hold does. The overlay's scrim has the label *Save the voice note* and a tap action, so a double tap saves.
- **Empty state.** `RelayMark(size: 56)`, *No notes yet* in `titleLarge`, *Tap New note to write one, or hold it to talk.* in muted body, and, with sending off, *Notes stay on this phone until you turn on sending in Settings.*
- **Sync dot.** A `_SyncDot` in `_CountLine`: accent and still for *Synced*; spark with a pulsing ring (an `AnimationController`, 1.4 s, repeat) for *Syncing*; a hollow muted ring for waiting and *Offline*; danger for *Key refused*. When `MediaQuery.disableAnimationsOf(context)` is true, the controller does not run. With sending off the line says *On this phone*, with no dot.
- **Settings groups.** A `_Group` widget: a 13 px 650 muted heading and a `Card` holding its rows, with no `Divider`. Groups: *Notes* (pin notes), *Voice notes* (the speech model row, with *Remove*), *Sending* (send my notes, health, calendar and its calendars, location history and its mode, where the phone sends, webhook and its problem, server, disconnect). The *Voice notes* group drops its title row: the heading says it, and the help line says the voice never leaves the phone. With sending off, the three dim rows get short help lines (below) and the card ends with *Health, Calendar and Location history work with Send my notes on.* With them on, the rows keep `sentLine`. *Disconnect this phone* is danger text.

  | Row | Help line, off |
  |---|---|
  | Pin notes to where I am | Each typed note keeps where you were. |
  | Health | Steps, heart rate, sleep and more. |
  | Calendar | Your phone's calendars. |
  | Location history | Where you go, also while the app is closed. |

  *Health: steps, heart rate, sleep and more* becomes *Health*, with the rest in its help line, so the title fits one line at 360 px.
- **Settings title.** Settings uses the same `SliverAppBar.large` with *Settings*, and a back button to *Notes*.
- **Other screens.** `ComposeScreen` becomes a plain page: back to *Notes*, *Save* filled accent at the top right, the field with no border, the first line drawn in 22 px 700 (a `TextEditingController` subclass that styles the first line in `buildTextSpan`; the saved text is unchanged), and a bottom toolbar with the paperclip in ink. `connect.dart` swaps its `Divider` for 24 px of space and a muted *Or*. Dialogs take 16 px corners through `dialogTheme`.
- **iPhone share sheet.** A `Brand.swift` in the extension with each token as a `UIColor(dynamicProvider:)` from the same hex values; `ShareCardView` sets the paper background, card fills with 16 px corners, a filled accent *Save* with on-accent text and 12 px corners, and `.font(.custom("Inter", size:))` per role. `InterVariable.ttf` and `OFL.txt` join the ShareExtension target's resources, and its `Info.plist` lists the font under `UIAppFonts`. The font adds about 0.9 MB to the extension, well inside the share extension's memory limit because a font is mapped, not loaded.
- **One color source, checked.** `wiki/brand.md` says each surface has one home for the colors; `Brand.swift` becomes the fourth. A Dart test reads `Brand.swift` and fails, naming the token, when a hex value differs from `BrandColors`. Alternative: generate the Swift file from `brand.dart`; rejected as more code than a 12-line check.

## Risks / Trade-offs

- **Bigger body text makes long screens longer.** Settings' shorter help lines offset it; `narrow_test.dart` keeps the 360 px check on the title and the Settings switch.
- **Tests find widgets by their words and gestures.** *Hold to talk* finders and the slide-off test go; the voice tests move to a 0.5 s hold on *New note*, a lift, and a tap. Each removed test is replaced by one for the new gesture in the same task, and the Decision log gets a `Check:` line if any is dropped.
- **A tap anywhere saves.** A tap meant for something else while recording saves the note; that is the person's ask, and *Cancel* sits apart in the card.
- **Long lists.** Grouping and search run over `relay.entries` on each build; a phone with thousands of notes may need the groups computed once per change. Not now: the list is this phone's own notes.
- **The iPhone font only shows on a device.** Widget tests can not see SwiftUI; the iPhone check after `/save` covers the share sheet only if its tour opens it, so the acceptance task names it.

## UX

### Use-case brief

Who: one person keeping short notes, voice notes and shares on their phone, often with one hand, many times a day; the same person opens Settings a few times a month. The job on the notes screen: catch a thought fast, then see that it is kept and whether it went. Done: the note is in the list, with *Sent* or *Waiting to send*. Context: phone first, light and dark. Common case: tap *New note*, or hold it to talk; less often, search for an old note. Edge cases: no speech model yet, sending off, a key refused, no network. Closest existing screen: Apple Notes' list on iOS 26, which the person named; board section 6 of the brand change for the colors.

### Flow

Open → tap *New note* → type → *Save* → back on the list with the note on top under *Today*. Or hold *New note* → buzz, mic → let go → speak → tap anywhere → the note shows *Writing the words…*, then its words. Find: tap *Search* → type → tap a row → read → back. Edge cases branch off as today: the model question, the snackbar messages.

### Hierarchy

- Notes: *New note* is the one accent fill; *Search* and ⋯ are quiet card shapes; the sync state is muted text with a word; row lines 2 and 3 are muted.
- Note page: no accent fill; *Play* is a quiet card row.
- Settings: no accent fill; switches show on in the accent, and the group headings are muted.
- New note: *Save*. Listening card: no fill; the tap anywhere is the action, *Cancel* is a quiet button. Share sheet: *Save*.

### Review

[review.html](review.html). What Changes: *A notes list like Apple Notes* (the live drawing, every screen and state), *One New note button*, *Search your notes*, *A ⋯ menu, and a page to read a note*, *Settings in three groups*, *The sync state says its name*, *The other screens match*, *The iPhone share sheet wears the brand*.

### Components

Flutter Material widgets themed by `brandTheme`, as today, with `SliverAppBar.large` and `MenuAnchor`. New: `NewNoteButton`, `ListeningOverlay`, `_SearchField`, `_DayGroup`, `_NoteRow`, `_CountLine` with `_SyncDot`, the note page, and `_Group` in Settings. Pure helpers in `days.dart`: `dayGroup` and `entryMatches`. Gone: `HoldToTalkButton`, `ListeningCard`, `RecordingSheet`, `_PageCard`, `_SyncChip`, `_LocalChip`. In SwiftUI: `Brand.swift`.
