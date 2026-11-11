# relay-sending Specification

## Purpose
Keep every Relay note on the phone unless the person chooses to send, and send only what they chose.

## Requirements

### Requirement: Signing in sends to one place the person picks

Sending SHALL start in one step: when the person signs in to Relay Everything or saves their own webhook, the phone SHALL send there, after the question about earlier notes. The app SHALL have no separate switch for sending. Notes SHALL go to that one place only, never both. Signed in to Relay Everything, health, location points, calendar events and photos SHALL go to Relay Everything, or, when the person turns on *Only to my own webhook* in *Webhooks*, only to their own webhook, never to both. The sign-in SHALL NOT ask where private data goes. The offline default, the earlier-notes question, and health and location only while sending SHALL work the same for both places.

#### Scenario: Signing in starts sending

- **WHEN** the person taps *Sign in to Relay Everything* in Settings, signs in, and picks *Only new notes*
- **THEN** the phone sends new notes to their server, and Settings shows their email

#### Scenario: Earlier notes with a webhook

- **WHEN** the person picks *Don't want an account? Use your own webhook* with 12 notes that never left the phone
- **THEN** the app asks whether to send the 12, sends them to the webhook only on a yes, and Settings says *My own webhook*

#### Scenario: Switching private data back to Relay Everything

- **WHEN** a signed-in person with *Only to my own webhook* on and 40 health samples waiting turns it off in *Webhooks*
- **THEN** the 40 samples and all later private data go to Relay Everything, and nothing more goes to the webhook from the phone

### Requirement: Signing out keeps what exists

*Sign out* and, for the person's own webhook, *Stop sending* SHALL stop all sending, keep every note written on the phone, and leave the server's copy untouched. *Stop sending* SHALL keep the webhook's address and secret on the phone, so the person can send there again without a new secret.

#### Scenario: Sign out and back in

- **WHEN** the person signs out and later signs in again
- **THEN** the server still holds the notes sent before, and the phone sends again with its new key

### Requirement: The app works offline by default

A newly installed Relay phone app SHALL let the person write and read notes with no key, no server and no connection, and SHALL make no network request while sending is off, except to get the speech model after the person agrees to it.

#### Scenario: First open with no key
- **WHEN** the person opens the app for the first time and writes a note
- **THEN** the note is saved and shown in the timeline, and the app asks for no key

#### Scenario: A week of notes with sending off
- **WHEN** the person writes notes, pins them, and opens Settings with sending off
- **THEN** the app sends nothing to any server and looks up no place names

#### Scenario: Voice notes with sending off
- **WHEN** sending is off and the person agrees to get the speech model, then makes voice notes
- **THEN** the only request is the model's download, and no voice note, recording or word leaves the phone

### Requirement: Health and location history only while sending

The app SHALL read health samples, calendar events for sending, and record location history only while sending is on, and SHALL keep no copy of any of them while sending is off.

#### Scenario: Sending is off
- **WHEN** the person has never turned sending on
- **THEN** the app asks for no health, calendar or background-location permission, and stores no samples, events or points

#### Scenario: Sending turned off with uploads waiting
- **WHEN** the person turns sending off while health samples, calendar events or location points are still waiting to go
- **THEN** the app deletes them, stops reading health and the calendar and recording location, and keeps every note

### Requirement: Earlier notes go only when the person says so

When the person turns sending on and notes exist that never went to the server, the app SHALL ask whether to send them, and SHALL send them only on a yes. When a phone that sent to the person's own webhook signs in to Relay Everything, the notes written on this phone that went only to the webhook SHALL count as earlier notes too. A note already on the person's Relay Everything space SHALL NOT be asked about or sent again.

#### Scenario: Only new notes
- **WHEN** the person turns sending on with 42 unsent notes and picks only new notes
- **THEN** none of the 42 is sent, and notes written after that are sent

#### Scenario: Turned on again later
- **WHEN** the person turns sending on again after a time with it off
- **THEN** the app asks again about every note that never went to the server and was not already waiting to send

#### Scenario: From the webhook to Relay Everything
- **WHEN** a phone sent 12 notes to the person's own webhook, then signs in to Relay Everything, and the person picks *Send them*
- **THEN** the 12 notes go to Relay Everything, oldest first, and the webhook gets none of them again from the phone
