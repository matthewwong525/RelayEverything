# Spec Delta

## Purpose
Lets a person delete a note on the Relay Everything phone app, with a short Undo, and removes it from the phone, the person's space, their other phones and their webhooks.

## ADDED Requirements

### Requirement: A note deletes from its menu or with a swipe

The note page's ⋯ menu SHALL offer *Delete*, and a swipe to the left on a note in any notes list SHALL delete that note. A delete SHALL ask no question: the note SHALL leave the list at once, and the list SHALL offer *Undo* for about five seconds. *Undo* SHALL bring the note back as it was, and nothing of the delete SHALL leave the phone. A note SHALL go off the phone only when the *Undo* time ends, also when the app closes during it.

#### Scenario: Delete from the menu
- **WHEN** the person opens a note, taps ⋯ and picks *Delete*
- **THEN** the note page closes, the note is gone from the list, and *Note deleted* shows with *Undo*

#### Scenario: Undo a swipe
- **WHEN** the person swipes a note to the left and taps *Undo* within the time
- **THEN** the note is back in its place with its words and files, and no delete is sent

### Requirement: A deleted note goes away everywhere

When a delete of a note already sent reaches the person's space, the server SHALL delete the note, its files and its recording, and it SHALL no longer show on the person's page, to their AI apps, or through the web API. Each signed-in phone SHALL drop the note at its next sync. A phone key SHALL delete any note in its own person's space, and no note in another space. A change to a note deleted since SHALL change nothing. A note that never left the phone SHALL be deleted on the phone only.

#### Scenario: Gone from the other phone
- **WHEN** a note is deleted on one phone, and the person's other phone syncs
- **THEN** the note is gone from the other phone and from the person's page

#### Scenario: An edit after a delete
- **WHEN** another phone sends a change to a note that was deleted
- **THEN** the note stays deleted, and the other phone drops its change and the note

### Requirement: Webhooks get a note deleted message

When the server deletes a note, it SHALL send one `note.deleted` message, with the note's id and when it was deleted, to every active webhook, in the same signed format as other messages. A message about the note still waiting to go SHALL NOT be sent after the delete. A receiver that ignores `note.deleted` SHALL keep working. A phone that sends to the person's own webhook SHALL send `note.deleted` there for a note it sent there.

#### Scenario: A webhook hears of a delete
- **WHEN** a sent note is deleted on the phone and the *Undo* time ends
- **THEN** each active webhook gets one `note.deleted` with that note's id

### Requirement: A delete waits while it can't be sent

A delete made while the phone is offline, or while sending is off, SHALL wait on the phone and SHALL be sent before the phone next syncs, so the note does not come back. While sending is off, the phone SHALL make no network call for it.

#### Scenario: Delete with sending off
- **WHEN** the person deletes a sent note with sending off, then later turns sending on with Relay Everything
- **THEN** the delete goes to the space first, and the note does not come back on this phone
