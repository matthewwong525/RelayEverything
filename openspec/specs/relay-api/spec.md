# relay-api Specification

## Purpose
Let a person's own scripts and other services read their Relay Everything data and add notes through one web API, each caller reaching only that person's space.

## Requirements

### Requirement: Other services read and add through one web API

Relay Everything SHALL offer a web API that answers the same questions as the AI connector: search notes, read one note, read notes in a time range, sum up a day, read health over time, read places, search saved chats and read one chat. It SHALL also add a typed note. It SHALL NOT change or delete any data, and SHALL NOT return a recording, a key, or a device's id. Each answer SHALL have the same size limits as the AI connector, with a way to read the next page.

#### Scenario: A script reads yesterday's notes
- **WHEN** a script with a person's API key asks for the notes from yesterday
- **THEN** it gets that person's notes from yesterday, at most one page, with a way to read the next

#### Scenario: A caller tries to delete
- **WHEN** a caller with a valid token or API key sends a request to delete or change a note
- **THEN** it is refused and the note stays as it is

### Requirement: Two ways in, each to one person's space

The API SHALL accept a token from a connected app, made by the same sign-in as the AI connector, or a person's API key. Each SHALL reach only the space of the person who connected the app or made the key. The API SHALL refuse a phone key, a chat key, a site session, an app the person disconnected, and an API key the person turned off.

#### Scenario: Two people's callers
- **WHEN** Ana's API key asks for a note id that is in Ben's space
- **THEN** the API answers that no note has this id, and returns nothing of Ben's

#### Scenario: A phone key on the API
- **WHEN** a request with a phone's key reaches the API
- **THEN** it is refused before any data is read

### Requirement: An added note is a note like any other

A note added through the API SHALL show on the person's page with the connected app's or the key's name as its device, and SHALL go to the person's webhooks as a new note in the same message format. A note sent again with the same caller's own id SHALL be stored once.

#### Scenario: A note from a service reaches a webhook
- **WHEN** a connected service adds a note and the person has a webhook
- **THEN** the webhook gets a new-note message for it, with the service's name as the device

#### Scenario: The same note sent twice
- **WHEN** a caller sends the same note again with the same id after losing the answer
- **THEN** one note is stored and the second answer says it was already added
