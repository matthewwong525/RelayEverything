## MODIFIED Requirements

### Requirement: A change to a sent note is sent

While sending is on, a change to a note already sent SHALL be sent once the person stops editing it, with the note's latest words and any files added. With Relay Everything picked, the server SHALL keep the new words in place of the old, and the page, the AI connector and the API SHALL read the new words. With the person's own webhook picked, the phone SHALL send a `note.updated` message there. A change made while offline or while a note waits to send SHALL go with the next send, and only the latest words SHALL arrive. A phone key SHALL be able to change any note in its own person's space, and SHALL add files only to a note it sent. When two changes of one note meet, the server SHALL keep the one made later and refuse the older one, whatever order they arrive in. A key SHALL NOT change a note in another person's space. With sending off, a change SHALL stay on the phone.

#### Scenario: Change a sent note
- **WHEN** sending to Relay Everything is on and the person changes a sent note's words
- **THEN** the note on the page shows the new words, and each of the person's webhooks gets one `note.updated` message

#### Scenario: Another device's note
- **WHEN** a phone key changes a note that another device or way in sent to the same person's space
- **THEN** the server keeps the new words, and each of the person's webhooks gets one `note.updated` message

#### Scenario: An older change
- **WHEN** a phone key sends a change made before the note's last change
- **THEN** the server refuses it, keeps the newer words, and sends no `note.updated` message

#### Scenario: Another person's note
- **WHEN** a phone key asks to change a note in another person's space
- **THEN** the server finds no such note, and the note stays as it was
