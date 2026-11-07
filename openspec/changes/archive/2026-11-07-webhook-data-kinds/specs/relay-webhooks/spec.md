## MODIFIED Requirements

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

## ADDED Requirements

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
