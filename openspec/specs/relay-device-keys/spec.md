# relay-device-keys Specification

## Purpose
Let each phone and the Pebble app reach Relay with a key of its own, reaching nothing else on the site, and revocable one at a time.

## Requirements

### Requirement: One key can be revoked alone

Revoking a device's key SHALL stop that device at its next request and leave other devices working.

#### Scenario: A lost phone
- **WHEN** Matthew revokes the Android phone's key
- **THEN** that phone's next sync is refused and the iPhone and Pebble app keep working

### Requirement: A device key adds only to its own person's space

A person SHALL make each device's key on their Relay Everything page, which SHALL show it once, or, for a phone, by signing in from the Relay Everything app and confirming that phone on the page. A key made from the app SHALL go to that phone only, through a code that works once and only for a few minutes, and SHALL never show. A device key SHALL reach only the routes that add data, and a key check that answers only that key's own device name. It SHALL add data only to the space of the person who made it, and SHALL NOT list, read or delete any note, recording, sample, point or chat. This SHALL hold on every Relay Everything server.

#### Scenario: A phone key tries to read notes
- **WHEN** a request with a phone's key asks for the timeline or a recording
- **THEN** it is refused, and the phone's sends still work

#### Scenario: A phone checks its key
- **WHEN** a phone connects and checks its key
- **THEN** the server answers with that key's device name and no data

#### Scenario: A key shown once
- **WHEN** a person closes the page that showed a new key
- **THEN** the page never shows that key again

#### Scenario: Connect by signing in from the app
- **WHEN** a person taps *Sign in to connect*, signs in, and taps *Connect* on *Connect this phone?*
- **THEN** the phone keeps its own new key, the page lists the phone among the devices, and no screen shows the key

#### Scenario: A connect code used twice or by another app
- **WHEN** a connect code is traded for a key a second time, after a few minutes, or without the secret the phone made when it started
- **THEN** the server refuses it and makes no key

### Requirement: Only live device keys and the checker pass as machines

The server SHALL refuse every machine key that is neither a device key still turned on nor its environment's checker. A key from a deleted account SHALL be refused.

#### Scenario: A key after its account is deleted
- **WHEN** a phone sends with a key whose account was deleted
- **THEN** the server refuses it and stores nothing

#### Scenario: The preview check
- **WHEN** the preview checker opens a preview
- **THEN** it reaches the site as before
