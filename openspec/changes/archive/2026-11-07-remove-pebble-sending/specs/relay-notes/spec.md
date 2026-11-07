## REMOVED Requirements

### Requirement: Signed ring notes are received once

**Reason**: The Pebble app no longer sends ring notes to a Relay Everything server: no one uses it, and Matthew's ring sends straight to WongOS.

**Migration**: None. Ring notes already stored stay, with their words, recordings and places. A Pebble app still set up to send gets a not-found answer; turn its webhook off in the Pebble app.

### Requirement: Every note carries a place when one is known

**Reason**: Only Pebble ring notes arrived without a place and took one later from location history. With that route gone, this requirement is replaced by *A note keeps the place it came with*.

**Migration**: None. A ring note that already has a place keeps it.

## ADDED Requirements

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
