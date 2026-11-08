# Spec Delta

## MODIFIED Requirements

### Requirement: The phone sends straight to one webhook the person sets

When the person picks their own webhook, the phone SHALL send each new note, each note's files, and, when turned on, health samples, calendar events, location points and new photos straight to that one address, and SHALL send nothing to a Relay Everything server.

#### Scenario: A note with webhook mode on
- **WHEN** the person picks their own webhook and writes a note
- **THEN** the receiver gets a `note.created` message for it, and no request goes to any Relay Everything server

#### Scenario: No account
- **WHEN** a person with no Relay Everything account or key picks their own webhook and saves its address and secret
- **THEN** the phone sends to it, and never asks them to sign in

#### Scenario: Health and places with webhook mode on
- **WHEN** health, the calendar and location history are on in webhook mode
- **THEN** the receiver gets `health.samples`, `calendar.events` and `location.points` messages, and nothing goes to the server

#### Scenario: Photos with webhook mode on
- **WHEN** *Photos* is on in webhook mode and the person takes a photo
- **THEN** the receiver gets a `photo.created` message with the photo, after the notes waiting before it, and nothing goes to the server

### Requirement: Nothing is lost when the receiver fails

The phone SHALL count a message as sent only after a 2xx answer. On any other answer, or no answer, it SHALL keep the message and every later one, in order, for a later round, and show the last failure in Settings. A file the receiver refuses as too large SHALL be dropped and shown, and the items after it go on. Photos SHALL wait apart from the other items: a photo the receiver refuses SHALL NOT hold back notes, and a photo it refuses as too large SHALL be dropped.

#### Scenario: The receiver is down
- **WHEN** the receiver answers 503 for a day
- **THEN** every waiting item stays on the phone in order, Settings shows the failure, and all of them go once it answers 2xx

#### Scenario: A file too large
- **WHEN** the receiver answers 413 to a note's file
- **THEN** that file is dropped, Settings says so, and the next items still go
