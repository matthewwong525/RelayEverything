## REMOVED Requirements

### Requirement: A device key adds only to its own person's space

**Reason**: A phone key now also reads its person's notes and changes any note in that space, for note sync.
**Migration**: Replaced by *A device key adds to its own person's space, and a phone key also syncs its notes*, which keeps every other limit.

## ADDED Requirements

### Requirement: A device key adds to its own person's space, and a phone key also syncs its notes

A person SHALL make each device's key on their Relay Everything page, which SHALL show it once, or, for a phone, by signing in from the Relay Everything app and confirming that phone on the page. A key made from the app SHALL go to that phone only, through a code that works once and only for a few minutes, and SHALL never show. A phone key or a chat key SHALL reach the routes that add data, and a key check that answers only that key's own device name. A phone key SHALL also read its person's notes, their files and old ring recordings, and change any note in that space. A key SHALL reach only the space of the person who made it, and SHALL NOT list, read or delete any health sample, place, calendar event, chat or photo, nor delete a note. This SHALL hold on every Relay Everything server.

#### Scenario: A phone key reads notes
- **WHEN** a request with a phone's key asks for the notes changed since its last sync
- **THEN** it gets its own person's notes, and no other person's

#### Scenario: A phone key tries to read health
- **WHEN** a request with a phone's key asks for the timeline's health, places, calendar, chats or a photo
- **THEN** it is refused, and the phone's sends still work

#### Scenario: A chat key tries to read notes
- **WHEN** a request with a chat key asks for notes
- **THEN** it is refused

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

#### Scenario: A phone key tries to delete photos
- **WHEN** a request with a phone's key asks to count or delete photos
- **THEN** it is refused, and the photos stay
