# Spec Delta

## MODIFIED Requirements

### Requirement: One device key can be turned off alone

Turning off a device's key SHALL stop that device at its next request and leave other devices working. Making a key on the Relay Everything page SHALL make an API key and give only the key, once, with no QR code and no signing secret; a phone or a computer SHALL get its key only by signing in.

#### Scenario: A lost phone
- **WHEN** Matthew signs out the Android phone
- **THEN** that phone's next sync is refused and the iPhone and Claude Code keep working

#### Scenario: A new phone key
- **WHEN** a person wants a key for a new phone
- **THEN** they sign in on the phone, the page offers no phone key or QR code, and *Add an API key* shows only an API key, once, with no signing secret

### Requirement: A device key adds to its own person's space, and a phone key also syncs its notes

A person SHALL make each device's key on their Relay Everything page, which SHALL show it once, or, for a phone, by signing in from the Relay Everything app and confirming that phone on the page. A key made from the app SHALL go to that phone only, through a code that works once and only for a few minutes, and SHALL never show. A phone key or a chat key SHALL reach the routes that add data, and a key check that answers only that key's own device name. A phone key SHALL also read its person's notes, their files and old ring recordings, and change or delete any note in that space. It SHALL also read the names of its person's phones and computers, with when each connected and when each computer last saved a chat, the names of their connected AI apps with the day each connected, the names of their webhooks, and their two notes email addresses, and nothing else about them: no webhook address, secret or send state, and no key. A phone key SHALL sign out one of its person's phones, and SHALL NOT sign out a computer or an API key, add a key, or add, change or disconnect an AI app or a webhook. A key SHALL reach only the space of the person who made it, and SHALL NOT list, read or delete any health sample, place, calendar event, chat or photo. A chat key or an API key SHALL NOT delete a note, and a phone key SHALL NOT delete a note in another person's space. This SHALL hold on every Relay Everything server.

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
- **WHEN** a person taps *Sign in*, signs in, and taps *Connect* on *Connect this phone?*
- **THEN** the phone keeps its own new key, the page lists the phone among the devices, and no screen shows the key

#### Scenario: A connect code used twice or by another app
- **WHEN** a connect code is traded for a key a second time, after a few minutes, or without the secret the phone made when it started
- **THEN** the server refuses it and makes no key

#### Scenario: A phone key tries to delete photos
- **WHEN** a request with a phone's key asks to count or delete photos
- **THEN** it is refused, and the photos stay

#### Scenario: A phone reads its person's connections
- **WHEN** a phone's key asks for its person's connections
- **THEN** the server answers with the names of the phones, computers, AI apps and webhooks, their dates, and both notes addresses, from that person's space only, and a chat key or an API key asking the same is refused

#### Scenario: A phone key deletes a note
- **WHEN** a request with a phone's key deletes a note from email in its person's space
- **THEN** the note and its files are gone from that space, and a chat key or an API key asking the same is refused

#### Scenario: A phone key tries another person's note
- **WHEN** a request with Ana's phone key asks to delete a note in Ben's space
- **THEN** Ben's note stays

#### Scenario: A phone signs out a lost phone
- **WHEN** a request with Ana's iPhone key asks to sign out her Pixel
- **THEN** the Pixel's key stops working, and her iPhone, her computers and Ben's phones keep working

#### Scenario: A phone key tries to sign out a computer
- **WHEN** a request with a phone's key asks to sign out a computer or an API key, or to disconnect an AI app
- **THEN** it is refused, and the computer, the key and the AI app keep working
