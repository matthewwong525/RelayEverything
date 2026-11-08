# relay-device-keys Specification

## Purpose
Let each phone and the Pebble app reach Relay with a key of its own, reaching nothing else on the site, and revocable one at a time.

## Requirements

### Requirement: One device key can be turned off alone

Turning off a device's key SHALL stop that device at its next request and leave other devices working. Making a key SHALL give only the key and its QR code text, and no signing secret.

#### Scenario: A lost phone
- **WHEN** Matthew turns off the Android phone's key
- **THEN** that phone's next sync is refused and the iPhone and Claude Code keep working

#### Scenario: A new phone key
- **WHEN** a person makes a phone key on the Relay Everything page
- **THEN** the page shows the key and its QR code once, and no signing secret

### Requirement: A device key adds to its own person's space, and a phone key also syncs its notes

A person SHALL make each device's key on their Relay Everything page, which SHALL show it once, or, for a phone, by signing in from the Relay Everything app and confirming that phone on the page. A key made from the app SHALL go to that phone only, through a code that works once and only for a few minutes, and SHALL never show. A phone key or a chat key SHALL reach the routes that add data, and a key check that answers only that key's own device name. A phone key SHALL also read its person's notes, their files and old ring recordings, and change any note in that space. It SHALL also read the names of its person's connected AI apps and webhooks, and nothing else about them: no webhook address, secret or send state. A key SHALL reach only the space of the person who made it, and SHALL NOT list, read or delete any health sample, place, calendar event, chat or photo, nor delete a note. This SHALL hold on every Relay Everything server.

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

#### Scenario: A phone reads its person's connections
- **WHEN** a phone's key asks for its person's connections
- **THEN** the server answers with the AI apps' and webhooks' names only, from that person's space, and a chat key or an API key asking the same is refused

### Requirement: Only live device keys and the checker pass as machines

The server SHALL refuse every machine key that is neither a device key still turned on nor its environment's checker. A key from a deleted account SHALL be refused.

#### Scenario: A key after its account is deleted
- **WHEN** a phone sends with a key whose account was deleted
- **THEN** the server refuses it and stores nothing

#### Scenario: The preview check
- **WHEN** the preview checker opens a preview
- **THEN** it reaches the site as before

### Requirement: An API key reads and adds notes through the API

A person SHALL be able to make an API key on their page, shown once like the other keys. An API key SHALL reach only the web API: it SHALL read the person's notes, health, places and saved chats there, and add notes, in that person's space only. It SHALL NOT reach the page's own routes, a phone's or a chat's send, or the AI connector's tools. Turning it off SHALL stop it at its next request.

#### Scenario: A home server reads with its key
- **WHEN** a script on a home server sends its API key to the web API and asks for today's notes
- **THEN** it gets the person's notes for today

#### Scenario: An API key on the page's routes
- **WHEN** a request with an API key asks the page's own timeline or recording route
- **THEN** it is refused
