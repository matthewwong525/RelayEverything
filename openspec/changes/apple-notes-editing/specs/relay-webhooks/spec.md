## MODIFIED Requirements

### Requirement: Stored data goes to each active webhook

After Relay Everything's server stores a note, a health batch, a location batch, calendar events or a photo, it SHALL send one message for it to each active webhook that takes that kind of data. Notes SHALL go to every active webhook. Health, location, calendar and photos SHALL go only to webhooks the owner ticked for them. Each photo SHALL go alone, in one message with its bytes. A changed or removed calendar event SHALL be sent again, marked as changed or removed. Only data that reached the server SHALL be sent: a note kept offline on a phone never goes out. A note changed on the phone that sent it SHALL be sent again as one `note.updated` message, with its latest words, to every active webhook; a receiver that ignores `note.updated` keeps working.

#### Scenario: A note with one webhook
- **WHEN** a phone's note is stored and one active webhook exists
- **THEN** that address gets a `note.created` message with the note's words, files, time and place within a minute

#### Scenario: Health not ticked
- **WHEN** a health batch is stored and the webhook takes notes only
- **THEN** that webhook gets no message for the batch

#### Scenario: A cancelled meeting
- **WHEN** a webhook takes the calendar and an event is deleted on the phone
- **THEN** after the phone's next send the webhook gets the event again, marked removed

#### Scenario: A note changed on the phone
- **WHEN** a stored note's words change from the phone that sent it
- **THEN** each active webhook gets one `note.updated` message with the new words, after the note's `note.created`
