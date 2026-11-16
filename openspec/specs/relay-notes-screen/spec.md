# relay-notes-screen Specification

## Purpose
The phone app's notes screen lists notes by day, finds a note on the phone, writes or talks from one *New note* button, and opens a note to read it.

## Requirements

### Requirement: Notes are listed by day

The phone app SHALL list the phone's notes newest first, in groups headed *Today*, *Yesterday*, *Previous 7 days*, *Previous 30 days*, and then by month, after the *Pinned* part when one shows. A pinned note SHALL show only in *Pinned*, not in its day group. Each note SHALL show its first line, then its time and the start of the rest of its words; a note with no typed words and a recording SHALL show the start of its first transcript in their place. A note with a recording SHALL also show a microphone and its first recording's length before the words. A row SHALL show no *Voice* or *Typed* tag and no *Sent*; while sending is on, a note that waits SHALL say *Waiting to send*.

#### Scenario: Notes from three days

- **WHEN** the phone holds a note from today, one from yesterday and one from four days ago
- **THEN** each shows under *Today*, *Yesterday* and *Previous 7 days*, newest first

#### Scenario: A voice note with notes

- **WHEN** a note holds a 0:51 recording and the typed words *Lamp: next steps*
- **THEN** its row shows *Lamp: next steps* as its first line, then a microphone and *0:51*, and not the transcript

#### Scenario: A sent note and a waiting note

- **WHEN** sending is on, one note is sent and one waits
- **THEN** the sent note's row says nothing about sending, and the other row says *Waiting to send*

#### Scenario: A pinned note from today

- **WHEN** the phone holds two notes from today and one of them is pinned
- **THEN** the pinned note shows under *Pinned* at the top, and *Today* holds only the other one

### Requirement: Search finds notes on the phone

The notes list SHALL have a search field that shows only the notes whose words, recording transcripts or file names hold the typed text, ignoring capital letters. Search SHALL read only the phone and SHALL make no network call.

#### Scenario: Search with no signal

- **WHEN** the phone has no connection and the person types *dentist* in *Search*
- **THEN** only the notes that hold *dentist* show, and no request leaves the phone

#### Scenario: A word said, not typed

- **WHEN** a note's recording's transcript holds *brass* and its typed words do not, and the person searches *brass*
- **THEN** the note shows

#### Scenario: Nothing matches

- **WHEN** the person searches for words no note holds
- **THEN** the list says no note holds them, and *Cancel* shows every note again

### Requirement: One button writes or talks

The notes list SHALL have one *New note* button. A press shorter than half a second SHALL open the page to write a note. A press held for half a second SHALL start a voice note, as the voice notes requirements say. The button SHALL show the hold's progress while it is pressed, and SHALL show a *Hold to talk* tip until the person's first voice note starts. A person who uses a screen reader SHALL be able to start a voice note from the same button.

#### Scenario: A tap writes

- **WHEN** the person taps *New note*
- **THEN** the page to write a note opens with the keyboard up, and nothing records

#### Scenario: The tip goes after the first voice note

- **WHEN** a person who has never made a voice note opens the notes list, then holds *New note* and saves a voice note
- **THEN** the *Hold to talk* tip shows on the first visit, and does not show again, also after the app restarts

### Requirement: A voice note plays from the top of its page

A note's page SHALL show the recording a voice note starts with as a card under the date, before the note's words, and every other recording as a card after the words, with the note's pictures and files in the order they were added. A card SHALL have one play and pause button, the sound waves of the recording, and the time, and under them a *Transcript* row that shows the first 2 lines of the recording's words. A tap on the row SHALL show all of the words and a copy button, and a second tap SHALL fold them again. The person SHALL be able to change the words of an open transcript; a change SHALL be kept and sent as a change of the note. While the words are being written the row SHALL say *Writing the words…*. The part of the waves that has played SHALL show in the accent text color. A tap or a drag on the waves SHALL move the playback to that point. While it plays, the time SHALL show how far it has played and the length; stopped, it SHALL show the length. The sound waves SHALL be read from the recording on the device, and SHALL NOT be kept or sent. With no recording on the device to read, the player SHALL show a plain line in place of the waves and still play. A note that starts with a recording SHALL show *Add notes…* under that card while its words are empty. The ⋯ menu and the bottom of the page SHALL have no *Play*.

#### Scenario: Play and skip

- **WHEN** the person opens a note with a 42-second recording, taps play, and then taps the middle of the waves
- **THEN** the recording plays, the button shows pause, and playback goes to about 0:21 with the time *0:21 / 0:42*

#### Scenario: Open the transcript

- **WHEN** the person opens a voice note whose transcript is five lines long and taps *Transcript*
- **THEN** all five lines show with a copy button, and a second tap shows only the first 2 lines again

#### Scenario: Pause

- **WHEN** a voice note plays and the person taps pause
- **THEN** the playback stops where it is, the played part of the waves stays, and play goes on from there

### Requirement: The notes list filters its notes and opens each one

The notes list SHALL have three filters at its top, *All*, *Voice* and *Photos and files*, each with how many notes it holds, and SHALL open on *All*. *All* SHALL show every note, *Voice* only notes with a recording, and *Photos and files* only notes with a photo or a file other than a recording. A note SHALL stay in *All* when the person adds a photo, a file, a recording or a link to it. The list SHALL keep its day groups, a way back to Home, and a search that finds notes in the picked filter only. A pull on the list SHALL sync while sending is on. A tap on a note SHALL open a page that shows its recordings, all of its words in their styles, and its pictures and files, each where the voice notes requirements place it. That page SHALL let the person change the note, as the note editing requirements say. The list SHALL show a note's first line and the start of the rest without style marks.

#### Scenario: A photo does not move a note

- **WHEN** the person adds a photo to a typed note in *All*
- **THEN** the note stays in *All* where it was, and *Photos and files* shows it too, with its count one higher

#### Scenario: Filter voice notes

- **WHEN** the list holds 6 notes, 2 of them with a recording, and the person taps *Voice*
- **THEN** only the 2 notes with a recording show, and *All 6* and *Voice 2* stay on the filters

#### Scenario: Back to Home

- **WHEN** the person opens *Notes* from Home, picks *Voice*, and taps *Home*
- **THEN** Home shows again, as they left it

#### Scenario: A note that starts with a heading

- **WHEN** a note's first line is a title and its next line is a checklist item *Eggs*
- **THEN** the list shows the title's words with no `#`, and *Eggs* with no `- [ ]`
