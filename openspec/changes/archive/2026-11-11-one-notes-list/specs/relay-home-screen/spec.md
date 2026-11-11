## MODIFIED Requirements

### Requirement: Home holds the notes folders and the phone's data

The phone app SHALL open on a *Home* screen with three groups of folders: one *Notes* row; *On this phone*, with *Location*, *Health*, *Calendar* and *Photos*; and *Other connections*, with *Connect your AI* and *Email notes*, in that order. Each row in *Other connections* SHALL carry one line that says what it does. Home SHALL have no *Connections* section and no row for sending or webhooks. The *Notes* row SHALL show how many notes the phone holds, and SHALL open the notes list with every note. Under the title, Home SHALL show the sync state only when notes wait or can't go, as the brand's sync state rule says, and no line when every note is sent or sending is off. Home SHALL have no *Voice notes* or *Shares* row: the notes list filters them. Home SHALL show no folder for a feature that does not work yet. A person SHALL be able to fold *On this phone* and *Other connections*, and the phone SHALL remember it. A tap on a section name SHALL fold or open it with no highlight behind the name, as in Apple Notes.

#### Scenario: Opening the app

- **WHEN** the person opens the app with 3 typed notes, 2 voice notes and 1 note with a photo
- **THEN** Home shows *Notes* 6, *On this phone* below it, then *Other connections* with *Connect your AI* and *Email notes*, each with its line, and no *Voice notes*, *Shares* or *Connections* row, and, with every note sent, no line under *Home*

#### Scenario: A first open

- **WHEN** a new install opens with sending off
- **THEN** Home shows *Notes* at 0 and *Location*, *Health*, *Calendar* and *Photos* as *Off*, and no request leaves the phone

## ADDED Requirements

### Requirement: One row stays at the top when the page scrolls

When Home or the notes list scrolls, the large title and the line under it SHALL go up with the page, and the top of the phone app SHALL be one row: the way back or the mark, the small title, and one small line under the title. No second line SHALL stay fixed under that row. In the notes list, the small line SHALL show the count of notes alone while every note is sent or sending is off, and the sync state's dot and words in place of the count while notes wait or can't go. On Home, the small line SHALL show the state only while notes wait or can't go, and nothing otherwise. The small line SHALL be words, not a button.

#### Scenario: A scrolled notes list

- **WHEN** sending is on, all 12 notes are sent, and the person scrolls the notes list down
- **THEN** the top is one row with *Home* to go back, *Notes*, and *12 notes* below it with no dot, and the notes slide under that row alone

#### Scenario: Notes wait while the list is scrolled

- **WHEN** sending is on, 3 notes wait, and the notes list is scrolled
- **THEN** the small line shows the waiting dot and *3 waiting* in place of the count

## REMOVED Requirements

### Requirement: Sync now sits beside the sync state

**Reason**: The sync state shows only when something is wrong, with no control beside it.

**Migration**: Notes send by themselves, as the note sync requirements say, and a pull down on Home or the notes list syncs now, as before.
