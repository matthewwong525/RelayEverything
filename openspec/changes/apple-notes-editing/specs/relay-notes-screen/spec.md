## MODIFIED Requirements

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
