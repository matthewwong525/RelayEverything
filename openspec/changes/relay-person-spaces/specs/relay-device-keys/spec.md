## REMOVED Requirements

### Requirement: A device key reaches only Relay
**Reason**: Keys now belong to one person and are made on the Relay Everything page; the rule must name the person's own space.
**Migration**: Replaced by *A device key adds only to its own person's space*.

### Requirement: Only devices and the checker pass as machines
**Reason**: On the shared server, device keys are no longer Cloudflare service tokens.
**Migration**: Replaced by *Only live device keys and the checker pass as machines*.

## ADDED Requirements

### Requirement: A device key adds only to its own person's space

A person SHALL make each device's key on their Relay Everything page, which SHALL show it once. A device key SHALL reach only the routes that add data, and a key check that answers only that key's own device name. It SHALL add data only to the space of the person who made it, and SHALL NOT list, read or delete any note, recording, sample, point or chat. This SHALL hold on every Relay Everything server.

#### Scenario: A phone key tries to read notes
- **WHEN** a request with a phone's key asks for the timeline or a recording
- **THEN** it is refused, and the phone's sends still work

#### Scenario: A phone checks its key
- **WHEN** a phone connects and checks its key
- **THEN** the server answers with that key's device name and no data

#### Scenario: A key shown once
- **WHEN** a person closes the page that showed a new key
- **THEN** the page never shows that key again

### Requirement: Only live device keys and the checker pass as machines

The server SHALL refuse every machine key that is neither a device key still turned on nor its environment's checker. A key from a deleted account SHALL be refused.

#### Scenario: A key after its account is deleted
- **WHEN** a phone sends with a key whose account was deleted
- **THEN** the server refuses it and stores nothing

#### Scenario: The preview check
- **WHEN** the preview checker opens a preview
- **THEN** it reaches the site as before
