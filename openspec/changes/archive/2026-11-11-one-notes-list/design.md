# Design

## Context

See proposal.md, Why. Today `NotesFolder` in `mobile/lib/screens/days.dart` is three views of the same notes (`all`, `voice`, `shares`), and `entryIn` puts a note in `shares` when it has a file or a link. Home (`home.dart`), the browser's left bar (`web/shell.dart`) and the list (`timeline.dart`) all read `NotesFolder.values`. A voice note plays through `Relay.play(recording)`: the phone's `PhonePlayer` in `voice/recorder.dart` and the browser's `playFromUrl` in `web/web_relay.dart`, both `just_audio`, with no pause, position or seek. The prototype diff, `.scratch/one-notes-list-prototype.diff` after `prototype.mjs finish`, holds the screens drawn for this plan.

## Goals / Non-Goals

**Goals:**
- One `NotesFolder` meaning: a filter of one list, not a place a note lives.
- One player widget for the phone and the browser, with a small playback API on `Relay`.
- One rule for the sync state: it shows only when the person can act on it.

**Non-Goals:**
- Hold to paste in the note editor (`flutter_quill`'s toolbar and clipboard): its own chat and change.
- No stored waveform, no new table or file, no change to the sync order.

## Decisions

- **Keep `NotesFolder` and rename its values**, `all('All')`, `voice('Voice')`, `files('Photos and files')`, not a new type. `entryIn` keeps its shape; `files` is `entry.files.isNotEmpty`, and the link regex goes. Home shows one row for `all`; the list holds the picked filter in its state and opens on the one it was given. A new enum would touch every caller for no gain.
- **Playback on `Relay`**: `Playback? get playback` (recording, position, playing), `pause()`, `seek(Duration)` and `waveOf(recording, {bars = 48})`, with defaults that do nothing, so fakes and the browser need only what they use. The controller listens to the `AudioPlayer`'s position and state streams and calls `notifyListeners`, so the player rebuilds as the list does today. One `AudioPlayer` stays: a second note's play stops the first.
- **The waves come from the WAV samples**: read the 16-bit PCM after the header, split it into 48 parts, take each part's RMS, and scale to the loudest. A file that is not a 16-bit PCM WAV, such as a ring's `.m4a`, gives an empty list and the player draws a plain line. The result is kept in memory for the open page only. Alternatives: a waveform package (a new dependency for 30 lines), or storing levels at record time (new data, and old notes would have none).
- **The browser gets the same `VoicePlayer`**, with `playback`, `pause` and `seek` on its own `AudioPlayer`, and `waveOf` left at its empty default, because it streams the recording and keeps no bytes.
- **`SyncLine.stateOf(relay)` decides the state once**: null when all is sent, when sending is off, or while it syncs with nothing waiting. Home leaves out its app bar's `bottom` when it is null, so the title does not jump; the list always keeps its count line. `_SyncNow` and its arrows test go.
- **No button sends or syncs.** `_SendNow`, `_SyncNow` and the bottom `BrandTag` row go, and `SyncLine`'s state is not a tap target. To keep a note kept offline from waiting for the next open, the controller listens to `connectivity_plus`'s `onConnectivityChanged` (already a dependency, used for photos) and calls `sync()` when the connection goes from none to any while notes wait and sending is on. `RefreshIndicator` stays: a gesture takes no space. Alternative: a timer every minute while notes wait, which spends battery and requests while offline.
- **A shared `TitleBar` replaces `SliverAppBar.large` on Home and the list.** It is a pinned `SliverAppBar` (`toolbarHeight` 64, `expandedHeight` 140) whose `flexibleSpace` reads `FlexibleSpaceBarSettings` to fade out the large title and `SyncLine` as they scroll, and fade in the small title with a `_SmallLine` under it. The cause of today's band is `SyncLine` in the pinned bar's `bottom:` slot, which always stays. Taken from the one-row-top prototype diff that the other chat handed over. Alternative: `CupertinoSliverNavigationBar`, which has no slot for a line under the small title.
- **The paperclip uses `MoreMenu`** with *Photos* and *Files*, not `showModalBottomSheet`, so it opens beside the button as the ⋯ menu does.
- **The search field's focused border** is the card color, not `accentText` at width 2.

## Risks / Trade-offs

- [A person relied on *Shares* to find links] → Search still finds a link's words; a link inside a note was never a share of its own.
- [No visible *Synced* can feel unsure on the first open] → *N waiting* and *Key refused* still show, and each note that waits says so on its row.
- [A connection that comes back with no internet behind it, such as a captive Wi-Fi] → the round fails as today and the note keeps waiting; the next open, keep, pull or hourly round sends it.
- [Reading a long WAV on the main isolate] → At most 5 minutes at 16 kHz mono is 9.6 MB; read it with `compute` so the page does not stall.
- [Position updates rebuild the whole list] → The player listens to a `ValueListenable` for the position, not the relay's whole notifier, if the tests show extra rebuilds.

## Migration Plan

None. Notes and recordings keep their shape. A person who had *Voice notes* open sees Home with one *Notes* row after the update.

## UX

### Use-case brief
A person who keeps typed and voice notes on their iPhone, often several a day. The job: find a note fast and play a voice note back, skipping to the part they need. Done is the note found and heard. The common case is a typed or a voice note in the last few days; the edge cases are a note that waits to send, and a recording with no waves to read.

### Flow
Home → *Notes* → (optional) *Voice*; as the list scrolls, one row stays at the top with the count or the state under the small title → tap a note → play, then tap the waves to skip. A note that waits sends by itself; a pull down on Home or the list syncs by hand.

### Hierarchy
- **Home:** *New note* is the one main action; *Notes* is the first row; no status line while all is well.
- **Notes list:** *New note* stays the one main action; the picked filter is ink, the others card; each row is the title, then the time, a microphone and length for a voice note, and the start of the words. *Waiting to send* is the only state on a row.
- **A voice note:** the date, then the player, then the words. The play button is accent-soft, not filled, so *New note* stays the one filled control.

### Review
[review.html](review.html). The What Changes items *One Notes list with filters*, *Rows with no tag*, *A voice player at the top* and *No sync buttons, and status only when something is wrong* hold the Before and After pictures.

### Components
- Existing: `FolderRow`, `SliverAppBar`, `MoreMenu`, `PillIconButton`, `SyncLine`, `_SyncDot`, `RefreshIndicator`.
- New: `TitleBar` and `_SmallLine` in `timeline.dart`, for the one row that stays when the page scrolls. `NoteFilters` (three `ChoiceChip`s with counts, ink when picked, as `wiki/brand.md` says for chips), `VoicePlayer` and `WavePainter` in `note_blocks.dart`, replacing `PlayRow`.
