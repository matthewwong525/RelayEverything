# relay-notes Specification

## Purpose
Receive every note Matthew captures, from the Pebble ring or typed on a phone, exactly once, with its words and recording.

## Requirements

### Requirement: The server takes no Pebble webhook

The server SHALL have no route for the Pebble app's Index webhook, and SHALL make and keep no Pebble signing secret.

#### Scenario: A Pebble app still sends
- **WHEN** a Pebble app posts a signed ring note to the old Pebble address with a live device key
- **THEN** the server refuses it, as it refuses a phone key at any address the key does not reach, and stores nothing

### Requirement: A note keeps no place

The server SHALL keep no place on a note. A note's answers, in the app, the web API, the AI connector and webhooks, SHALL hold no place of its own; a reader SHALL find where a note was written from location history, by the note's time. A new note that comes with a latitude and longitude, from the web API, the AI connector or an older phone, SHALL be kept, and its place SHALL be kept as one location point of the sending device at the note's time, with its name when one came, and not on the note. A location point that already exists for that device and time SHALL be kept as it is.

#### Scenario: A script sends a note with a place
- **WHEN** a script sends a note written at 9:41 with a latitude, a longitude and the name *Queen St W*
- **THEN** the note is kept with no place, location history gains one point at 9:41 named *Queen St W*, and each webhook ticked for location gets that point

#### Scenario: The AI reads one note
- **WHEN** an AI app reads one note written at 9:41
- **THEN** the note has no place field, and the answer lists the stays near 9:41

### Requirement: Places on notes move into location history

When the server is updated, each note that holds a place SHALL give one location point of its device at the note's time, with the note's coordinates, accuracy and place name, and the note SHALL then keep no place. This SHALL happen once, in every person's space, and SHALL send no webhook message. It SHALL NOT be undone.

#### Scenario: A note with a place from before
- **WHEN** a space holds a note from 9:41 at Queen St W, and the server is updated
- **THEN** location history holds a point at 9:41 named Queen St W, the note has no place, and no webhook gets a message for it

#### Scenario: A point already there
- **WHEN** the same device already has a location point at the note's exact time
- **THEN** that point stays as it was, and the note still keeps no place
