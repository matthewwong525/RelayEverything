## MODIFIED Requirements

### Requirement: A device key adds only to its own person's space

A person SHALL make each device's key on their Relay Everything page, which SHALL show it once. A device key SHALL reach only the routes that add data, and a key check that answers only that key's own device name. It SHALL add data only to the space of the person who made it, and SHALL NOT list, read or delete any note, recording, sample, point, chat or photo. This SHALL hold on every Relay Everything server.

#### Scenario: A phone key tries to read notes
- **WHEN** a request with a phone's key asks for the timeline or a recording
- **THEN** it is refused, and the phone's sends still work

#### Scenario: A phone checks its key
- **WHEN** a phone connects and checks its key
- **THEN** the server answers with that key's device name and no data

#### Scenario: A key shown once
- **WHEN** a person closes the page that showed a new key
- **THEN** the page never shows that key again

#### Scenario: A phone key tries to delete photos
- **WHEN** a request with a phone's key asks to count or delete photos
- **THEN** it is refused, and the photos stay
