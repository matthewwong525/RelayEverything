# relay-phone-webhook Specification

## Purpose
Let the phone send notes, files, health, calendar events and places straight to one webhook the person sets, in the same signed format as the server, with nothing going through a Relay Everything server.

## Requirements

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

### Requirement: Phone messages match the server's format and signing

Every message the phone sends SHALL be a format v1 body, signed by the Standard Webhooks scheme with the secret the person set, so a receiver built for the server's webhooks takes it unchanged. A message sent again SHALL keep its `webhook-id` and body.

#### Scenario: A receiver checks a phone message
- **WHEN** a receiver checks a phone message with the secret and a Standard Webhooks library
- **THEN** the check passes, and the body matches the published v1 schema

#### Scenario: A retry after no signal
- **WHEN** a message fails for lack of signal and goes again in a later round
- **THEN** both tries have the same `webhook-id` and body

### Requirement: The phone sets up its webhook safely

The phone SHALL take only an `https://` address with no user name or password in it, and SHALL keep the secret only in the phone's secure key store. A private or home address SHALL be allowed. *Send a test* SHALL send a signed `webhook.test` message and show the receiver's answer. The setup SHALL be the same short form from the sign-in's *Don't want an account? Use your own webhook* and from *Webhooks* on the Account page: the address, a secret made on the phone to copy, *Send a test* and *Save*.

#### Scenario: An http address
- **WHEN** the person types an address that starts with `http://`
- **THEN** the phone refuses it and says the address must start with `https://`

#### Scenario: A test to a home receiver
- **WHEN** the person sets `https://192.168.1.20/relay` and taps *Send a test*
- **THEN** the phone sends the test and shows the answer's status

### Requirement: Nothing is lost when the receiver fails

The phone SHALL count a message as sent only after a 2xx answer. On any other answer, or no answer, it SHALL keep the message and every later one, in order, for a later round, and show the last failure in Settings. A file the receiver refuses as too large SHALL be dropped and shown, and the items after it go on. Photos SHALL wait apart from the other items: a photo the receiver refuses SHALL NOT hold back notes, and a photo it refuses as too large SHALL be dropped.

#### Scenario: The receiver is down
- **WHEN** the receiver answers 503 for a day
- **THEN** every waiting item stays on the phone in order, Settings shows the failure, and all of them go once it answers 2xx

#### Scenario: A file too large
- **WHEN** the receiver answers 413 to a note's file
- **THEN** that file is dropped, Settings says so, and the next items still go

### Requirement: A signed-in phone sends to no webhook itself

Signed in to Relay Everything, the phone SHALL send notes, their files, health, location points, stays and trips, calendar events and photos only to Relay Everything, and SHALL send nothing to any webhook itself. Relay Everything SHALL send each kind on only to the webhooks the person ticked for it. The phone SHALL keep its own webhook's address and secret while signed in, and SHALL use them again only after the person signs out and picks their own webhook. A phone that had *Only to my own webhook* on before the update SHALL send its waiting and later health, places, calendar and photos to Relay Everything, and SHALL show one message, once, that says so and opens *Webhooks*.

#### Scenario: Signed in with a webhook kept
- **WHEN** a signed-in person whose phone keeps a webhook writes a note and has health and photos on
- **THEN** the note, the health samples and the photos reach Relay Everything, and the phone's receiver gets no message from the phone

#### Scenario: A phone that had the choice on
- **WHEN** a phone that sent health only to its own webhook updates, with 40 health samples waiting, and opens
- **THEN** the 40 samples and later ones go to Relay Everything, one message says that everything now goes through Relay Everything, and the message does not show again
