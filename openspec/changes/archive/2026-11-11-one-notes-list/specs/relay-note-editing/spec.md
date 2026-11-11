## REMOVED Requirements

### Requirement: Tap Waiting to send to send now

**Reason**: Notes send by themselves, so a note's page has no button to send it.

**Migration**: A waiting note sends when the app opens or comes back, when a note is kept, when the connection comes back, and on a pull down; the notes list says *Waiting to send* on its row until then.

## ADDED Requirements

### Requirement: A note's page says nothing about sending

A note's page SHALL show only its date at the top. It SHALL show no *Sent*, no *Waiting to send*, no *Send now* and no *Voice* or *Typed* tag, and its ⋯ menu SHALL have no item to send or sync.

#### Scenario: A waiting note

- **WHEN** the person opens a note that waits to send
- **THEN** the top of the page shows only the date, and ⋯ has no *Send now*

#### Scenario: A sent note

- **WHEN** the person opens a note that is sent
- **THEN** the top of the page shows only the date, and the page has no *Sent* line and no tag
