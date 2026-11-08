# relay-webhooks Specification

## Purpose
Send the Relay data the server holds to addresses the owner adds, in one versioned, signed format, so the owner's own database keeps a reliable copy.

## Requirements

### Requirement: Stored data goes to each active webhook

After Relay Everything's server stores a note, a health batch, a location batch or calendar events, it SHALL send one message for it to each active webhook that takes that kind of data. Notes SHALL go to every active webhook. Health, location and calendar SHALL go only to webhooks the owner ticked for them. A changed or removed calendar event SHALL be sent again, marked as changed or removed. Only data that reached the server SHALL be sent: a note kept offline on a phone never goes out. A note changed on the phone that sent it SHALL be sent again as one `note.updated` message, with its latest words, to every active webhook; a receiver that ignores `note.updated` keeps working.

#### Scenario: A note with one webhook
- **WHEN** a phone's note is stored and one active webhook exists
- **THEN** that address gets a `note.created` message with the note's words, files, time and place within a minute

#### Scenario: Health not ticked
- **WHEN** a health batch is stored and the webhook takes notes only
- **THEN** that webhook gets no message for the batch

#### Scenario: A cancelled meeting
- **WHEN** a webhook takes the calendar and an event is deleted on the phone
- **THEN** after the phone's next send the webhook gets the event again, marked removed

#### Scenario: A note changed on the phone
- **WHEN** a stored note's words change from the phone that sent it
- **THEN** each active webhook gets one `note.updated` message with the new words, after the note's `note.created`

### Requirement: One versioned, signed format

Every message SHALL be a JSON body with `version`, `type`, `timestamp` and `data`, signed by the Standard Webhooks scheme with the webhook's own secret. Every note, sample and point SHALL carry a stable id, so a resent message updates the same row. The format SHALL be published on the public Relay Everything website with a machine-readable schema and an example receiver. The published schema SHALL accept fields it does not list. Until the public release, version 1 MAY change in any way, and the website SHALL say so; after it, a change that breaks a receiver SHALL raise `version`.

#### Scenario: A receiver checks a message
- **WHEN** a receiver checks the signature with the secret it was shown and a Standard Webhooks library
- **THEN** the check passes, and it fails for a changed body or a different secret

#### Scenario: The same note sent twice
- **WHEN** a retry sends a note the receiver already stored
- **THEN** both messages have the same `webhook-id`, body and note id

#### Scenario: A field the schema does not list
- **WHEN** a receiver checks a message that holds a field added after it saved the schema
- **THEN** the message still passes the published schema

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

### Requirement: A test shows the answer at once

*Send a test* SHALL send a signed `webhook.test` message right away and show the address's answer, or the error, to the owner.

#### Scenario: A wrong address
- **WHEN** the owner sends a test to an address that answers 404
- **THEN** the page shows the 404, and no data is sent

### Requirement: Each person manages only their own webhooks, and only safe addresses

Only the signed-in person whose space holds a webhook SHALL add, change, test, pause or remove it, or read its deliveries; a device key and every other person SHALL be refused. A webhook SHALL send only its own person's data. A webhook address SHALL be `https` and SHALL NOT point at `localhost`, a private or link-local network, or Relay Everything's own site. A webhook's secret SHALL be shown once, when it is made or replaced, and never again.

#### Scenario: A device key tries to add a webhook
- **WHEN** a phone's device key calls the add-webhook route
- **THEN** the server refuses it and adds nothing

#### Scenario: Another person's data
- **WHEN** Ben stores a note and Ana has a webhook
- **THEN** Ana's webhook gets nothing from Ben

#### Scenario: An address on a private network
- **WHEN** a person adds `https://192.168.1.10/hook` or `http://db.example.com`
- **THEN** the server refuses it and says why

### Requirement: A note's files go as their own messages

Format v1 SHALL include a `note.file` message that holds one file of a note: the note's id, the file's id, name, type and size, and its contents in base64. The server SHALL send it to every active webhook for each file whose bytes it stores, and the phone's own webhook mode SHALL send it for each file it holds, always after the note's `note.created`. The `note.created` message SHALL keep listing the note's files. When an address answers 413 to a `note.file`, that file SHALL be skipped, the webhook SHALL name it with its last answer, and the file SHALL stay in Relay Everything; any other failure SHALL be retried like every message. Files stored before the server sent `note.file` SHALL be sent once. The published schema and the example receiver SHALL include `note.file`, and the example receiver SHALL keep each listed file, with its bytes once they come.

#### Scenario: A note with a photo
- **WHEN** a phone's note with one photo is stored, then the photo's bytes, and one active webhook exists
- **THEN** that address gets the `note.created` that lists the photo, then a `note.file` with the photo's bytes and the same file id

#### Scenario: A receiver that takes only small bodies
- **WHEN** an address answers 413 to a 20 MB file and 200 to everything else
- **THEN** the webhook skips that file, names it on its card, and sends the next note

#### Scenario: The example receiver saves a file
- **WHEN** the example receiver gets a `note.created` that lists a file and then a `note.file` for that note
- **THEN** it keeps the file's name from the first message and saves its bytes beside the note from the second

### Requirement: Every kind of data is listed once, with all its parts

Each kind of data a person's space holds SHALL have one entry that names its webhook tick, its message types, its web API routes, its AI connector tools and its docs page. The repository's checks SHALL fail when a kind lacks one of these parts and its entry does not list that part as missing, and SHALL fail when a part listed as missing exists. The webhook form and card SHALL show the ticks from this list.

#### Scenario: A new kind without docs
- **WHEN** a kind is added with a tick, messages, a route and a tool, but no docs page
- **THEN** the checks fail and name the kind and the missing page

#### Scenario: Known gaps
- **WHEN** files, photos and chats have no webhook messages and their entries list webhooks as missing
- **THEN** the checks pass, and the list shows what a later change must add

### Requirement: A new kind reaches a webhook only when ticked

A kind added after a webhook was made SHALL NOT go to that webhook until the owner ticks it. Notes SHALL keep going to every webhook.

#### Scenario: A webhook made for notes only
- **WHEN** a webhook takes notes only and calendar events are stored
- **THEN** that webhook gets no calendar message until the owner ticks Calendar

### Requirement: Receivers can ignore what they do not know

The published docs SHALL tell a receiver to answer 2xx to a message type it does not know, to keep fields it does not know, and to accept a new value in a list. The example receiver SHALL answer 2xx to an unknown message type and keep its body as a raw row.

#### Scenario: The example receiver gets a new type
- **WHEN** the example receiver gets a correctly signed message of a type it does not know
- **THEN** it answers 2xx and stores the message's type and body as one raw row
