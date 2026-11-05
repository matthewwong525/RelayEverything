## MODIFIED Requirements

### Requirement: A device key reaches only Relay

A device key SHALL pass the site's login only to Relay's routes that add data, and to a key check that answers only that key's own device name. It SHALL NOT list, read or delete any note, recording, sample, point or chat; every other page and route SHALL refuse it. This SHALL hold on every Relay server, Matthew's and each install.

#### Scenario: A phone key tries another app
- **WHEN** a request with a phone's key asks for another app's route
- **THEN** it is refused

#### Scenario: A phone key tries to read notes
- **WHEN** a request with a phone's key asks for the timeline or a recording
- **THEN** it is refused, and the phone's sends still work

#### Scenario: A phone checks its key
- **WHEN** a phone connects and checks its key
- **THEN** the server answers with that key's device name and no data
