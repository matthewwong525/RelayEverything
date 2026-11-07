# relay-notes Specification

## Purpose
Receive every note Matthew captures, from the Pebble ring or typed on a phone, exactly once, with its words, recording and place.

## Requirements

### Requirement: A note keeps the place it came with

A note SHALL keep the location its phone sent with it, or none. The server SHALL NOT give a note a place later from location history, and SHALL NOT change the place of a note it already holds.

#### Scenario: A typed note with a place
- **WHEN** a phone sends a typed note with its location
- **THEN** the timeline shows the note at that place

#### Scenario: A location batch after an old ring note
- **WHEN** a location batch arrives with points near the time of a stored ring note that has no place
- **THEN** the ring note still has no place, and no webhook gets a message about it

### Requirement: The server takes no Pebble webhook

The server SHALL have no route for the Pebble app's Index webhook, and SHALL make and keep no Pebble signing secret.

#### Scenario: A Pebble app still sends
- **WHEN** a Pebble app posts a signed ring note to the old Pebble address with a live device key
- **THEN** the server refuses it, as it refuses a phone key at any address the key does not reach, and stores nothing
