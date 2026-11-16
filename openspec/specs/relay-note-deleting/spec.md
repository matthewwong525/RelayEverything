# relay-note-deleting Specification

## Purpose
Lets a person delete a note on the Relay Everything phone app, with a short Undo, and removes it from the phone, the person's space, their other phones and their webhooks.

## Requirements

### Requirement: A delete waits while it can't be sent

A delete made while the phone is offline, or while sending is off, SHALL wait on the phone and SHALL be sent before the phone next syncs, so the note does not come back. While sending is off, the phone SHALL make no network call for it.

#### Scenario: Delete with sending off
- **WHEN** the person deletes a sent note with sending off, then later turns sending on with Relay Everything
- **THEN** the delete goes to the space first, and the note does not come back on this phone

### Requirement: An open note's page closes when its note is gone

When a note leaves the phone while its page is open, such as a voice note with no speech, the page SHALL close and show the page under it, and leaving SHALL keep nothing of that note.

#### Scenario: A voice note with no speech
- **WHEN** a voice note's page is open and the phone finds no speech in its recording
- **THEN** the page closes, the page under it shows, and the app says it heard no speech

### Requirement: A delete moves a note to Recently Deleted

The note page's ⋯ menu SHALL offer *Delete*, and a swipe to the left on a note in any notes list SHALL delete that note. A delete SHALL ask no question and show no message: the note SHALL leave the list at once and move to *Recently Deleted*, with its words, files and recording. A note the person empties of words and leaves, with no file or recording, SHALL be deleted for good and SHALL NOT go to *Recently Deleted*.

#### Scenario: Delete from the menu
- **WHEN** the person opens a note, taps ⋯ and picks *Delete*
- **THEN** the note page closes, the note is gone from the list, no bar shows, and the note is in *Recently Deleted*

#### Scenario: An emptied note
- **WHEN** the person removes every word from a note with no file and goes back
- **THEN** the note is gone, and it is not in *Recently Deleted*

### Requirement: A deleted note leaves every list and app

A note in *Recently Deleted* SHALL show only in *Recently Deleted*, on every one of the person's signed-in phones, their Macs and their page, after each syncs. It SHALL NOT show in a notes list, in search, to their AI apps, or through the web API's note reads. When a note is deleted for good, the server SHALL delete the note, its files and its recording, and each device SHALL drop it at its next sync. A phone key SHALL delete or recover any note in its own person's space, and no note in another space. A change to a note deleted for good SHALL change nothing. A note that never left the phone SHALL be in *Recently Deleted* on that phone only.

#### Scenario: In Recently Deleted on the other phone
- **WHEN** a note is deleted on one phone, and the person's other phone syncs
- **THEN** the note is in *Recently Deleted* on the other phone, not in its notes, and the AI apps no longer find it

#### Scenario: An edit after a delete for good
- **WHEN** another phone sends a change to a note that was deleted for good
- **THEN** the note stays deleted, and the other phone drops its change and the note

### Requirement: Webhooks hear of a delete and a recover

When a note moves to *Recently Deleted* on the server, the server SHALL send one `note.deleted` message, with the note's id and when it was deleted, to every active webhook, in the same signed format as other messages. When a note in *Recently Deleted* is recovered, the server SHALL send one `note.recovered` message with the whole note. A delete for good SHALL send no further message. A message about the note still waiting to go SHALL NOT be sent after the delete. A receiver that ignores `note.deleted` or `note.recovered` SHALL keep working. A phone that sends to the person's own webhook SHALL send `note.deleted` and `note.recovered` there for a note it sent there.

#### Scenario: A webhook hears of a delete and a recover
- **WHEN** a sent note is deleted, and then recovered from *Recently Deleted*
- **THEN** each active webhook gets one `note.deleted` and then one `note.recovered` with that note's id and words

### Requirement: Recently Deleted keeps a note for 30 days

Home, and the left bar on the web page and the Mac, SHALL show a *Recently Deleted* row with its count only while it holds a note. Its page SHALL say that notes stay there for 30 days, and SHALL list its notes by the day they were deleted. A swipe to the left on a note SHALL offer *Recover* and *Delete*; ⋯ SHALL offer *Recover All* and *Delete All*. *Delete* and *Delete All* SHALL ask first, because they can't be undone. A recovered note SHALL go back to the notes list as it was. A deleted note SHALL open to read only; a tap in its words SHALL ask the person to recover it first. Thirty days after its delete, a note SHALL be deleted for good, with its files and recording, on the server and on each device, also with sending off.

#### Scenario: Recover a note
- **WHEN** the person opens *Recently Deleted*, swipes a note to the left and taps *Recover*
- **THEN** the note is back in the notes list with its words and files, and *Recently Deleted* no longer shows it

#### Scenario: The 30 days end
- **WHEN** a note has been in *Recently Deleted* for 30 days
- **THEN** it is deleted for good with its files, on the server and on every device, and the row leaves Home if it held no other note

### Requirement: A shake or ⌘Z undoes a delete

On an iPhone, a shake after a delete SHALL show an alert, *Undo Delete Note*, with *Cancel* and *Undo*. *Undo* SHALL move the last deleted note back from *Recently Deleted*, as it was. On the Mac and the web page, ⌘Z, or Ctrl+Z on Windows, SHALL undo the last delete when no note's words are being edited. With no delete to undo, a shake SHALL show nothing. Android SHALL have no shake undo.

#### Scenario: Shake after a swipe
- **WHEN** the person swipes a note away and shakes the iPhone, then taps *Undo*
- **THEN** the note is back in its place in the list, and is not in *Recently Deleted*
