# Spec Delta

## Purpose

Send the Relay data the server holds to addresses the owner adds, in one versioned, signed format, so the owner's own database keeps a reliable copy.

## ADDED Requirements

### Requirement: Stored data goes to every active webhook

After Relay's server stores a note, a health batch or a location batch, it SHALL send one message for it to each active webhook that takes that kind of data. Notes SHALL go to every active webhook. Health and location SHALL go only to webhooks the owner ticked for them. Only data that reached the server SHALL be sent: a note kept offline on a phone never goes out.

#### Scenario: A ring note with one webhook
- **WHEN** a ring note is stored and one active webhook exists
- **THEN** that address gets a `note.created` message with the note's words, recording, time and place within a minute

#### Scenario: Health not ticked
- **WHEN** a health batch is stored and the webhook takes notes only
- **THEN** that webhook gets no message for the batch

### Requirement: One versioned, signed format

Every message SHALL be a JSON body with `version`, `type`, `timestamp` and `data`, signed by the Standard Webhooks scheme with the webhook's own secret. Every note, sample and point SHALL carry a stable id, so a resent message updates the same row. The format SHALL be published on the public Relay website with a machine-readable schema and an example receiver, and a change that breaks a receiver SHALL raise `version`.

#### Scenario: A receiver checks a message
- **WHEN** a receiver checks the signature with the secret it was shown and a Standard Webhooks library
- **THEN** the check passes, and it fails for a changed body or a different secret

#### Scenario: The same note sent twice
- **WHEN** a retry sends a note the receiver already stored
- **THEN** both messages have the same `webhook-id`, body and note id

### Requirement: Nothing is skipped, and failures are retried, then shown

Each webhook SHALL get every item it takes, in the order Relay stored them, with none skipped, however long its address was down. A send that gets no 2xx answer SHALL be retried with growing waits for about 24 hours. After that the webhook SHALL show as failing, with the last answer and how many items wait, until the owner tries again; then it SHALL send from where it stopped. A slow or failing address SHALL NOT delay storing data or sending to other webhooks.

#### Scenario: The database is down for an hour
- **WHEN** the address answers 503 for an hour and then 200
- **THEN** the message arrives after the address recovers, and the webhook shows as working

#### Scenario: Down for two days
- **WHEN** the address fails for more than a day
- **THEN** the webhook shows as failing with its last answer and the number waiting, and *Try again now* sends every waiting item in order

### Requirement: Past data is sent on request

A new webhook SHALL get only data stored after it was added. When the owner asks to send past data from a date, Relay SHALL send every note, and the ticked health and location, stored since that date, in the same format.

#### Scenario: Catching up a new database
- **WHEN** the owner adds a webhook and sends past data from 1 October
- **THEN** the address gets every note since 1 October, then new notes as they arrive

### Requirement: Only the owner manages webhooks, and only safe addresses

Only a signed-in person with access to the Relay app SHALL add, change, test, pause or remove a webhook, or read its deliveries; a device key SHALL be refused. A webhook address SHALL be `https` and SHALL NOT point at `localhost`, a private or link-local network, or Relay's own site. A webhook's secret SHALL be shown once, when it is made or replaced, and never again.

#### Scenario: A device key tries to add a webhook
- **WHEN** a phone's device key calls the add-webhook route
- **THEN** Relay refuses it and adds nothing

#### Scenario: An address on a private network
- **WHEN** the owner adds `https://192.168.1.10/hook` or `http://db.example.com`
- **THEN** Relay refuses it and says why

### Requirement: A test shows the answer at once

*Send a test* SHALL send a signed `webhook.test` message right away and show the address's answer, or the error, to the owner.

#### Scenario: A wrong address
- **WHEN** the owner sends a test to an address that answers 404
- **THEN** the page shows the 404, and no data is sent
