## MODIFIED Requirements

### Requirement: A voice note plays from the top of its page

A note's page SHALL show the recording a voice note starts with as a card under the date, before the note's words, and every other recording as a card after the words, with the note's pictures and files in the order they were added. A card SHALL have one play and pause button, the sound waves of the recording, and the time. A recording with words SHALL show under them a *Transcript* row that shows none of the words, and a tap on the row SHALL open the recording's own page. The tap SHALL show no ink splash. The recording's page SHALL show all of the words as plain text, with no field border, the date and the length, a copy button, a way back to the note, and the player. On the phone's own note, the person SHALL be able to change the words on that page; a change SHALL be kept and sent as a change of the note. While the words are being written the card SHALL say *Writing the words…*. The part of the waves that has played SHALL show in the accent text color. A tap or a drag on the waves SHALL move the playback to that point. While it plays, the time SHALL show how far it has played and the length; stopped, it SHALL show the length. The sound waves SHALL be read from the recording on the device, and SHALL NOT be kept or sent. With no recording on the device to read, the player SHALL show a plain line in place of the waves and still play. A note that starts with a recording SHALL show *Add notes…* under that card while its words are empty. The ⋯ menu and the bottom of the page SHALL have no *Play*.

#### Scenario: Play and skip

- **WHEN** the person opens a note with a 42-second recording, taps play, and then taps the middle of the waves
- **THEN** the recording plays, the button shows pause, and playback goes to about 0:21 with the time *0:21 / 0:42*

#### Scenario: Open the transcript

- **WHEN** the person opens a voice note whose transcript is five lines long and taps *Transcript*
- **THEN** the recording's page opens with all five lines as plain text, a copy button and the player, and the note's card showed none of the words

#### Scenario: Fix a word on the recording's page

- **WHEN** the person opens the recording's page of a note made on this phone, changes *fab* to *lab*, and goes back
- **THEN** the card's recording keeps *lab*, and with sending on the change goes to the space as a change of the note

#### Scenario: Pause

- **WHEN** a voice note plays and the person taps pause
- **THEN** the playback stops where it is, the played part of the waves stays, and play goes on from there
