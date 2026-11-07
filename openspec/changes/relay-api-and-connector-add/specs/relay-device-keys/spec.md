## MODIFIED Requirements

### Requirement: A device key adds only to its own person's space

A person SHALL make each device's key on their Relay Everything page, which SHALL show it once. A phone key or a chat key SHALL reach only the routes that add data, and a key check that answers only that key's own device name. It SHALL add data only to the space of the person who made it, and SHALL NOT list, read or delete any note, recording, sample, point or chat. This SHALL hold on every Relay Everything server.

#### Scenario: A phone key tries to read notes
- **WHEN** a request with a phone's key asks for the timeline or a recording
- **THEN** it is refused, and the phone's sends still work

#### Scenario: A phone checks its key
- **WHEN** a phone connects and checks its key
- **THEN** the server answers with that key's device name and no data

#### Scenario: A key shown once
- **WHEN** a person closes the page that showed a new key
- **THEN** the page never shows that key again

## ADDED Requirements

### Requirement: An API key reads and adds notes through the API

A person SHALL be able to make an API key on their page, shown once like the other keys. An API key SHALL reach only the web API: it SHALL read the person's notes, health, places and saved chats there, and add notes, in that person's space only. It SHALL NOT reach the page's own routes, a phone's or a chat's send, or the AI connector's tools. Turning it off SHALL stop it at its next request.

#### Scenario: A home server reads with its key
- **WHEN** a script on a home server sends its API key to the web API and asks for today's notes
- **THEN** it gets the person's notes for today

#### Scenario: An API key on the page's routes
- **WHEN** a request with an API key asks the page's own timeline or recording route
- **THEN** it is refused
