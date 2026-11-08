# relay-note-sync Specification

## Purpose
Give every phone signed in to Relay Everything the same notes from its person's space, with changes from any phone, while the app stays offline by default.

## Requirements

### Requirement: A signed-in phone gets every note in its space

While sending is on and Relay Everything is picked, the phone app SHALL get every note in its person's space, from any device or way in, and each change to one, and SHALL show each note with where it came from. A phone that syncs for the first time SHALL get all the notes already there. A note the phone sent itself SHALL show once, never twice. New notes and changes SHALL come in when the app opens or comes back, when the person pulls down the list, and in the background round.

#### Scenario: A note from the other phone
- **WHEN** a person writes a note on their iPhone, and later opens the app on their Pixel, signed in with sending on
- **THEN** the Pixel lists the note, marked as from the iPhone

#### Scenario: A new phone
- **WHEN** a person signs in on a new phone that has 300 notes in its space
- **THEN** the phone lists all 300 notes, with the words, place and file list of each

### Requirement: Any note changes on any phone, and the newer change wins

A synced phone SHALL let the person change any note in their space, whichever device or way in made it. The server SHALL keep each change, and every synced phone, the page, the AI connector and the API SHALL then show the new words. When two changes of one note meet, the one made later SHALL win on every device, and the older one SHALL NOT replace it, however late it arrives.

#### Scenario: An email note changed on a phone
- **WHEN** a person fixes a typo in a note that came by email, on a synced phone
- **THEN** their page and their other phones show the fixed words

#### Scenario: A change made offline arrives late
- **WHEN** the iPhone changes a note offline at 9:00, the Pixel changes the same note at 9:30, and the iPhone sends its change at 10:00
- **THEN** both phones and the page show the Pixel's 9:30 words

### Requirement: A synced note's files open on tap

A synced phone SHALL list each note's files by name, type and size, and SHALL download a file only when the person opens it. A recording the server never got, such as a phone's own voice recording, SHALL stay only on the phone that made it.

#### Scenario: A boarding pass from email
- **WHEN** a person opens a synced email note on their phone and taps its PDF
- **THEN** the phone downloads the PDF and opens it, and no other file of that note is downloaded

### Requirement: Every synced change goes to the webhooks

Each note and each change of a note that reaches the server from any device SHALL go to each of the person's active webhooks, as for any note, so a person can have sync and their own database together.

#### Scenario: A change from the Pixel
- **WHEN** a person changes a note on their Pixel and has one webhook on their page
- **THEN** the webhook gets one `note.updated` message with the new words

### Requirement: No sync with sending off or with the person's own webhook

With sending off, the phone app SHALL make no network call to get notes. With the person's own webhook picked, the phone SHALL send only there and SHALL NOT get notes from any Relay Everything server. Turning sending off SHALL keep the notes already on the phone.

#### Scenario: Sending off
- **WHEN** sending is off and another phone adds a note
- **THEN** this phone makes no network call and does not show the note

#### Scenario: Own webhook picked
- **WHEN** the person picks *My own webhook*
- **THEN** the phone gets no notes from the server, and Settings says so and points to adding the webhook on the page

### Requirement: Signing out removes notes from elsewhere

When a person signs out of the phone app or forgets its server, the phone SHALL delete the notes and downloaded files that came from other devices or ways in, and SHALL keep the notes written on that phone.

#### Scenario: A phone handed on
- **WHEN** a person signs out on a phone that has 20 of its own notes and 280 synced ones
- **THEN** the phone keeps its 20 notes and no longer has the 280
