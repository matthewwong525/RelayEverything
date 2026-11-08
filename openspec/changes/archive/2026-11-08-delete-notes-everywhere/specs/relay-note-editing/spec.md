## MODIFIED Requirements

### Requirement: A note edits in place

A tap on a note's words SHALL put the cursor there and bring up the keyboard, on the same page that shows the note. A new note SHALL open on that page with the keyboard up and its first line styled as a title. Each change SHALL be kept on the phone within two seconds of a pause in typing, and when the person leaves the page, with no *Save* button. A note left with no words and no files SHALL be deleted when the person leaves it, as Apple Notes does, with *Undo*: a note never sent and with no upload waiting SHALL be deleted on the phone only, with any change of it still waiting, so it is never sent; a sent note, or one whose first upload waits or is on its way, SHALL be deleted everywhere, as a delete from the ⋯ menu is. A voice note left with no words SHALL keep its recording. A voice note's words SHALL be editable, and its recording SHALL stay unchanged.

#### Scenario: Fix a word and leave
- **WHEN** the person opens a note, taps a word, types a fix and taps back
- **THEN** the list shows the note with the fix, and the fix is still there after the app restarts

#### Scenario: An empty new note
- **WHEN** the person opens a new note and leaves without typing or adding a file
- **THEN** no note is added to the list

#### Scenario: An emptied note
- **WHEN** the person deletes every word of a note that has no files or recording, and leaves
- **THEN** the note is gone from the list with *Undo*, and when the *Undo* time ends a sent copy is deleted from the page and webhooks get `note.deleted`
