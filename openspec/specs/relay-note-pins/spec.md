# relay-note-pins Specification

## Purpose
TBD - created by archiving change note-editor-pins-find. Update Purpose after archive.

## Requirements

### Requirement: A note pins from its menu or a swipe

The phone app SHALL let the person pin a note from *Pin Note* in its ⋯ menu, and from a swipe right on its row in the notes list. A pinned note's ⋯ menu and swipe SHALL offer *Unpin Note*, which unpins it. A pin SHALL be kept on the phone at once, with no network call needed, and SHALL NOT change the note's words or its time.

#### Scenario: Pin from the note
- **WHEN** the person opens a note, taps ⋯ and taps *Pin Note*
- **THEN** the note shows under *Pinned* in the notes list, and its ⋯ menu now reads *Unpin Note*

#### Scenario: Unpin with a swipe
- **WHEN** the person swipes right on a pinned note's row
- **THEN** the note leaves *Pinned* and shows again under its day

### Requirement: Pinned notes show in a part at the top that folds

While any shown note is pinned, the notes list SHALL start with a *Pinned* part above the day groups, holding each pinned note once, newest first, and those notes SHALL NOT also show under their day. A tap on the *Pinned* heading SHALL fold the part to its heading, and a second tap SHALL open it. The fold SHALL stay after the app closes. Search and the filters SHALL apply to pinned notes as to the others. With no pinned note shown, the list SHALL have no *Pinned* part.

#### Scenario: Fold and reopen the app
- **WHEN** the person taps *Pinned* to fold it, closes the app and opens it again
- **THEN** *Pinned* shows folded, with its notes hidden, and a tap shows them

#### Scenario: Search finds no pinned note
- **WHEN** two notes are pinned and the person searches for words only an unpinned note holds
- **THEN** the list shows that note under its day and no *Pinned* part

### Requirement: A pin follows the person to every device

While the phone sends to Relay Everything, a pin or unpin SHALL reach the server, and every synced phone and the person's Relay Everything page SHALL show the note in or out of *Pinned*. A pin or unpin on the page SHALL reach the phones the same way. When two pin changes of one note meet, the one made later SHALL win on every device. A pin change SHALL NOT send a webhook message. Signed out, or sending only to the person's own webhook, a pin SHALL stay on the phone.

#### Scenario: Pinned on the iPhone, shown on the page
- **WHEN** the person pins a note on their synced iPhone
- **THEN** their Relay Everything page and their other phones show it under *Pinned*, and no webhook gets a message

#### Scenario: Two pin changes meet
- **WHEN** the iPhone unpins a note offline at 9:00, the page pins it at 9:30, and the iPhone sends its unpin at 10:00
- **THEN** the note stays pinned on both
