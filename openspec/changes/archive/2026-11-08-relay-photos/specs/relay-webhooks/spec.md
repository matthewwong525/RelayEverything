# Spec Delta

## MODIFIED Requirements

### Requirement: Stored data goes to each active webhook

After Relay Everything's server stores a note, a health batch, a location batch, calendar events or a photo, it SHALL send one message for it to each active webhook that takes that kind of data. Notes SHALL go to every active webhook. Health, location, calendar and photos SHALL go only to webhooks the owner ticked for them. Each photo SHALL go alone, in one message with its bytes. A changed or removed calendar event SHALL be sent again, marked as changed or removed. Only data that reached the server SHALL be sent: a note kept offline on a phone never goes out. The server SHALL send no `note.updated` message; format version 1 SHALL still describe it, as no longer sent, so a receiver that handles it keeps working.

#### Scenario: A note with one webhook
- **WHEN** a phone's note is stored and one active webhook exists
- **THEN** that address gets a `note.created` message with the note's words, files, time and place within a minute

#### Scenario: Health not ticked
- **WHEN** a health batch is stored and the webhook takes notes only
- **THEN** that webhook gets no message for the batch

#### Scenario: A cancelled meeting
- **WHEN** a webhook takes the calendar and an event is deleted on the phone
- **THEN** after the phone's next send the webhook gets the event again, marked removed

### Requirement: Every kind of data is listed once, with all its parts

Each kind of data a person's space holds SHALL have one entry that names its webhook tick, its message types, its web API routes, its AI connector tools and its docs page. The repository's checks SHALL fail when a kind lacks one of these parts and its entry does not list that part as missing, and SHALL fail when a part listed as missing exists. The webhook form and card SHALL show the ticks from this list.

#### Scenario: A new kind without docs
- **WHEN** a kind is added with a tick, messages, a route and a tool, but no docs page
- **THEN** the checks fail and name the kind and the missing page

#### Scenario: Known gaps
- **WHEN** files and chats have no webhook messages and their entries list webhooks as missing
- **THEN** the checks pass, and the list shows what a later change must add
