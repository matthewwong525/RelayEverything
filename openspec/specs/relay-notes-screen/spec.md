# relay-notes-screen Specification

## Purpose
The phone app's notes screen lists notes by day, finds a note on the phone, writes or talks from one *New note* button, and opens a note to read it.

## Requirements

### Requirement: Notes are listed by day

The phone app SHALL list the phone's notes newest first, in groups headed *Today*, *Yesterday*, *Previous 7 days*, *Previous 30 days*, and then by month. Each note SHALL show its first line, its time, the start of the rest of its words, whether it is a voice or a typed note, and, while sending is on, *Sent* or *Waiting to send*.

#### Scenario: Notes from three days

- **WHEN** the phone holds a note from today, one from yesterday and one from four days ago
- **THEN** each shows under *Today*, *Yesterday* and *Previous 7 days*, newest first

### Requirement: Search finds notes on the phone

The notes list SHALL have a search field that shows only the notes whose words, place or file names hold the typed text, ignoring capital letters. Search SHALL read only the phone and SHALL make no network call.

#### Scenario: Search with no signal

- **WHEN** the phone has no connection and the person types *dentist* in *Search*
- **THEN** only the notes that hold *dentist* show, and no request leaves the phone

#### Scenario: Nothing matches

- **WHEN** the person searches for words no note holds
- **THEN** the list says no note holds them, and *Cancel* shows every note again

### Requirement: One button writes or talks

The notes list SHALL have one *New note* button. A press shorter than half a second SHALL open the page to write a note. A press held for half a second SHALL start a voice note, as the voice notes requirements say. A person who uses a screen reader SHALL be able to start a voice note from the same button.

#### Scenario: A tap writes

- **WHEN** the person taps *New note*
- **THEN** the page to write a note opens with the keyboard up, and nothing records

### Requirement: The ⋯ menu and a page to read a note

The notes list SHALL have a ⋯ menu with *Settings*, and, while sending is on, *Sync now*, and *Open your Relay Everything page* when the phone sends to a Relay Everything server. A tap on a note SHALL open a page that shows all of its words in their styles, its pictures and files, and *Play* for a voice note's recording. That page SHALL let the person change the note, as the note editing requirements say. The list SHALL show a note's first line and the start of the rest without style marks.

#### Scenario: Read a voice note

- **WHEN** the person taps a voice note in the list
- **THEN** its page shows all of its words and *Play*, and *Play* plays the recording from the phone

#### Scenario: The menu with sending off

- **WHEN** sending is off and the person opens the ⋯ menu
- **THEN** it shows *Settings* and no *Sync now* or page link

#### Scenario: A note that starts with a heading

- **WHEN** a note's first line is a title and its next line is a checklist item *Eggs*
- **THEN** the list shows the title's words with no `#`, and *Eggs* with no `- [ ]`
