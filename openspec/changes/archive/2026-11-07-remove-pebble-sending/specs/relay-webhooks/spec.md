## REMOVED Requirements

### Requirement: Stored data goes to every active webhook

**Reason**: Its scenario uses a ring note, which the server no longer receives. It is replaced by *Stored data goes to each active webhook*, with the same rule.

**Migration**: None.

## ADDED Requirements

### Requirement: Stored data goes to each active webhook

After Relay Everything's server stores a note, a health batch or a location batch, it SHALL send one message for it to each active webhook that takes that kind of data. Notes SHALL go to every active webhook. Health and location SHALL go only to webhooks the owner ticked for them. Only data that reached the server SHALL be sent: a note kept offline on a phone never goes out. The server SHALL send no `note.updated` message; format version 1 SHALL still describe it, as no longer sent, so a receiver that handles it keeps working.

#### Scenario: A note with one webhook
- **WHEN** a phone's note is stored and one active webhook exists
- **THEN** that address gets a `note.created` message with the note's words, files, time and place within a minute

#### Scenario: Health not ticked
- **WHEN** a health batch is stored and the webhook takes notes only
- **THEN** that webhook gets no message for the batch
