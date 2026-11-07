## MODIFIED Requirements

### Requirement: The AI reads but never changes

Every connector tool but one SHALL be marked read-only and SHALL only read notes, health samples, locations and saved chats. The one other tool SHALL add a typed note, and only for an app connected with the words that say it can add notes. No tool SHALL edit or delete any Relay Everything data, and recordings SHALL NOT be returned.

#### Scenario: The AI is asked to delete a note
- **WHEN** a chat asks the AI to delete or edit a Relay note
- **THEN** no connector tool can do it and the note stays as it is

#### Scenario: The AI saves a note
- **WHEN** a person asks a connected AI app to save something as a note
- **THEN** the note shows on their page with the app's name as its device

#### Scenario: An app connected before notes could be added
- **WHEN** an app connected before this change tries to add a note
- **THEN** it is refused with a message to connect again, and its reads still work

### Requirement: Each person connects only their own space

The connector SHALL admit a sign-in by any person with an account on its server, and each connection SHALL reach only that person's space, through its tools and through the web API. Its tools SHALL refuse every request that has no valid connector token, including one carrying a device key, an API key or a site session.

#### Scenario: Two people connect
- **WHEN** Ana and Ben each connect Claude and ask for today's notes
- **THEN** each gets only their own notes

#### Scenario: Someone with no account signs in
- **WHEN** a person with no account completes the connector sign-in on a server with sign-up off
- **THEN** no connection is made and no data is returned

#### Scenario: A request with no token
- **WHEN** a request reaches the connector without a valid token
- **THEN** it is refused before any data is read
