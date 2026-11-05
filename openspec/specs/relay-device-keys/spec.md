# relay-device-keys Specification

## Purpose
Let each phone and the Pebble app reach Relay with a key of its own, reaching nothing else on the site, and revocable one at a time.

## Requirements

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

### Requirement: One key can be revoked alone

Revoking a device's key SHALL stop that device at its next request and leave other devices working.

#### Scenario: A lost phone
- **WHEN** Matthew revokes the Android phone's key
- **THEN** that phone's next sync is refused and the iPhone and Pebble app keep working

### Requirement: Only devices and the checker pass as machines

The site SHALL refuse every service token that is neither an unrevoked device key nor its environment's checker, and the checker SHALL keep its usual access.

#### Scenario: A staging phone key after a staging reset
- **WHEN** a staging reset empties the list of devices and a staging phone sends with its old key
- **THEN** the site refuses it, and it does not count as the preview checker

#### Scenario: The preview check
- **WHEN** the preview checker opens a preview
- **THEN** it reaches the site as before
