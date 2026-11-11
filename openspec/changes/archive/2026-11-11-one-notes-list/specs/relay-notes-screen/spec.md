## MODIFIED Requirements

### Requirement: Notes are listed by day

The phone app SHALL list the phone's notes newest first, in groups headed *Today*, *Yesterday*, *Previous 7 days*, *Previous 30 days*, and then by month. Each note SHALL show its first line, then its time and the start of the rest of its words. A voice note SHALL also show a microphone and its length before the words. A row SHALL show no *Voice* or *Typed* tag and no *Sent*; while sending is on, a note that waits SHALL say *Waiting to send*.

#### Scenario: Notes from three days

- **WHEN** the phone holds a note from today, one from yesterday and one from four days ago
- **THEN** each shows under *Today*, *Yesterday* and *Previous 7 days*, newest first

#### Scenario: A sent note and a waiting note

- **WHEN** sending is on, one note is sent and one waits
- **THEN** the sent note's row says nothing about sending, and the other row says *Waiting to send*

## REMOVED Requirements

### Requirement: A notes folder lists its notes and opens each one

**Reason**: Home has one *Notes* row, so there are no notes folders: one list filters the notes, and a voice note plays from a player, not *Play*.

**Migration**: *The notes list filters its notes and opens each one* and *A voice note plays from the top of its page* hold this rule now. The iPhone share sheet's look stays in the brand's *The iPhone share sheet wears the brand*.

## ADDED Requirements

### Requirement: A voice note plays from the top of its page

A voice note's page SHALL show its voice player under the date, before the words: one play and pause button, the sound waves of the recording, and the time. The part of the waves that has played SHALL show in the accent text color. A tap or a drag on the waves SHALL move the playback to that point. While it plays, the time SHALL show how far it has played and the length; stopped, it SHALL show the length. The sound waves SHALL be read from the recording on the phone, and SHALL NOT be kept or sent. With no recording to read, the player SHALL show a plain line in place of the waves and still play. The ⋯ menu and the bottom of the page SHALL have no *Play*.

#### Scenario: Play and skip

- **WHEN** the person opens a 42-second voice note, taps play, and then taps the middle of the waves
- **THEN** the recording plays from the phone, the button shows pause, and playback goes to about 0:21 with the time *0:21 / 0:42*

#### Scenario: Pause

- **WHEN** a voice note plays and the person taps pause
- **THEN** the playback stops where it is, the played part of the waves stays, and play goes on from there

### Requirement: The notes list filters its notes and opens each one

The notes list SHALL have three filters at its top, *All*, *Voice* and *Photos and files*, each with how many notes it holds, and SHALL open on *All*. *All* SHALL show every note, *Voice* only voice notes, and *Photos and files* only notes with a photo or a file. A note SHALL stay in *All* when the person adds a photo, a file or a link to it. The list SHALL keep its day groups, a way back to Home, and a search that finds notes in the picked filter only. A pull on the list SHALL sync while sending is on. A tap on a note SHALL open a page that shows all of its words in their styles, its pictures and files, and, for a voice note, its voice player. That page SHALL let the person change the note, as the note editing requirements say. The list SHALL show a note's first line and the start of the rest without style marks.

#### Scenario: A photo does not move a note

- **WHEN** the person adds a photo to a typed note in *All*
- **THEN** the note stays in *All* where it was, and *Photos and files* shows it too, with its count one higher

#### Scenario: Filter voice notes

- **WHEN** the list holds 6 notes, 2 of them voice notes, and the person taps *Voice*
- **THEN** only the 2 voice notes show, and *All 6* and *Voice 2* stay on the filters

#### Scenario: Back to Home

- **WHEN** the person opens *Notes* from Home, picks *Voice*, and taps *Home*
- **THEN** Home shows again, as they left it

#### Scenario: A note that starts with a heading

- **WHEN** a note's first line is a title and its next line is a checklist item *Eggs*
- **THEN** the list shows the title's words with no `#`, and *Eggs* with no `- [ ]`
