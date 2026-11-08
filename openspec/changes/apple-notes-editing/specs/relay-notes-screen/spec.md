## MODIFIED Requirements

### Requirement: A notes folder lists its notes and opens each one

A notes folder SHALL open a list of only its notes, grouped by day as before, with a way back to Home and a search that finds notes in that folder only. A pull on the list SHALL sync while sending is on. A tap on a note SHALL open a page that shows all of its words in their styles, its pictures and files, and *Play* for a voice note's recording. That page SHALL let the person change the note, as the note editing requirements say. The list SHALL show a note's first line and the start of the rest without style marks.

#### Scenario: Read a voice note

- **WHEN** the person taps a voice note in the list
- **THEN** its page shows all of its words and *Play*, and *Play* plays the recording from the phone

#### Scenario: Back to Home

- **WHEN** the person opens *Voice notes* from Home and taps *Home*
- **THEN** Home shows again, as they left it

#### Scenario: A note that starts with a heading

- **WHEN** a note's first line is a title and its next line is a checklist item *Eggs*
- **THEN** the list shows the title's words with no `#`, and *Eggs* with no `- [ ]`
