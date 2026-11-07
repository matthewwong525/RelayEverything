# relay-phone-webhook Specification

## Purpose
Let the phone send notes, files, health and places straight to one webhook the person sets, in the same signed format as the server, with nothing going through a Relay Everything server.

## Requirements

### Requirement: The phone sends straight to one webhook the person sets

When the person picks their own webhook, the phone SHALL send each new note, each note's files, and, when turned on, health samples and location points straight to that one address, and SHALL send nothing to a Relay Everything server.

#### Scenario: A note with webhook mode on
- **WHEN** the person picks their own webhook and writes a note
- **THEN** the receiver gets a `note.created` message for it, and no request goes to any Relay Everything server

#### Scenario: No account
- **WHEN** a person with no Relay Everything account or key picks their own webhook and saves its address and secret
- **THEN** the phone sends to it, and never asks them to sign in

#### Scenario: Health and places with webhook mode on
- **WHEN** health and location history are on in webhook mode
- **THEN** the receiver gets `health.samples` and `location.points` messages, and nothing goes to the server

### Requirement: Phone messages match the server's format and signing

Every message the phone sends SHALL be a format v1 body, signed by the Standard Webhooks scheme with the secret the person set, so a receiver built for the server's webhooks takes it unchanged. A message sent again SHALL keep its `webhook-id` and body.

#### Scenario: A receiver checks a phone message
- **WHEN** a receiver checks a phone message with the secret and a Standard Webhooks library
- **THEN** the check passes, and the body matches the published v1 schema

#### Scenario: A retry after no signal
- **WHEN** a message fails for lack of signal and goes again in a later round
- **THEN** both tries have the same `webhook-id` and body

### Requirement: The phone sets up its webhook safely

The phone SHALL take only an `https://` address with no user name or password in it, and SHALL keep the secret only in the phone's secure key store. A private or home address SHALL be allowed. *Send a test* SHALL send a signed `webhook.test` message and show the receiver's answer.

#### Scenario: An http address
- **WHEN** the person types an address that starts with `http://`
- **THEN** the phone refuses it and says the address must start with `https://`

#### Scenario: A test to a home receiver
- **WHEN** the person sets `https://192.168.1.20/relay` and taps *Send a test*
- **THEN** the phone sends the test and shows the answer's status

### Requirement: Nothing is lost when the receiver fails

The phone SHALL count a message as sent only after a 2xx answer. On any other answer, or no answer, it SHALL keep the message and every later one, in order, for a later round, and show the last failure in Settings. A file the receiver refuses as too large SHALL be dropped and shown, and the items after it go on.

#### Scenario: The receiver is down
- **WHEN** the receiver answers 503 for a day
- **THEN** every waiting item stays on the phone in order, Settings shows the failure, and all of them go once it answers 2xx

#### Scenario: A file too large
- **WHEN** the receiver answers 413 to a note's file
- **THEN** that file is dropped, Settings says so, and the next items still go
