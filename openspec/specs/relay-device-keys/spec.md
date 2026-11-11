# relay-device-keys Specification

## Purpose
Let each phone and the Pebble app reach Relay with a key of its own, reaching nothing else on the site, and revocable one at a time.

## Requirements

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

### Requirement: A computer's key saves chats and reads through the web API

A person SHALL get a computer's key only by confirming a sign-in link that the computer started, after seeing the computer's name and a short code that the computer also shows; the page's *Add a device* SHALL NOT make one. The key SHALL go to that computer only, through a request that works once and only for a few minutes and that only the computer that started it can finish, and SHALL never show. A computer's key SHALL add chats and their saves, and SHALL read the person's notes, health, sleep, workouts, places, calendar and saved chats and add notes through the web API, in that person's space only. It SHALL NOT reach a phone's routes, the page's own routes or the AI connector's tools, and SHALL NOT change or delete anything. An older chat key SHALL keep only adding chats. Turning a computer's key off SHALL stop it at its next request.

#### Scenario: A computer reads notes
- **WHEN** a computer's key asks the web API for today's notes
- **THEN** it gets its own person's notes for today, and no other person's

#### Scenario: Someone else's link
- **WHEN** a person confirms a link that another computer started, and that computer asks for its key after the few minutes, or without the secret it started with
- **THEN** no key is given

#### Scenario: An older chat key tries to read
- **WHEN** a chat key made before this change asks the web API for notes
- **THEN** it is refused, and its chat sends still work
