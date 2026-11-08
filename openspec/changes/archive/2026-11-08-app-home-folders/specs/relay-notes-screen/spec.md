## MODIFIED Requirements

### Requirement: One button writes or talks

Home and each notes list SHALL have one *New note* button. A press shorter than half a second SHALL open the page to write a note. A press held for half a second SHALL start a voice note, as the voice notes requirements say. A person who uses a screen reader SHALL be able to start a voice note from the same button.

#### Scenario: A tap writes

- **WHEN** the person taps *New note*
- **THEN** the page to write a note opens with the keyboard up, and nothing records

## REMOVED Requirements

### Requirement: The ⋯ menu and a page to read a note

**Reason**: The ⋯ menu moves to Home, in `relay-home-screen`; the page to read a note stays, under its own name below.
**Migration**: None: the menu keeps the same items, one tap further back.

## ADDED Requirements

### Requirement: A notes folder lists its notes and opens each one

A notes folder SHALL open a list of only its notes, grouped by day as before, with a way back to Home and a search that finds notes in that folder only. A pull on the list SHALL sync while sending is on. A tap on a note SHALL open a page that shows all of its words, pictures and files, and *Play* for a voice note's recording. That page SHALL not change the note.

#### Scenario: Read a voice note

- **WHEN** the person taps a voice note in the list
- **THEN** its page shows all of its words and *Play*, and *Play* plays the recording from the phone

#### Scenario: Back to Home

- **WHEN** the person opens *Voice notes* from Home and taps *Home*
- **THEN** Home shows again, as they left it
