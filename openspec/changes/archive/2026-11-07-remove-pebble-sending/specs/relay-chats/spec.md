## MODIFIED Requirements

### Requirement: A chat key reaches only the chat routes
Relay SHALL accept saved chats only from an unrevoked device key made for chats. A chat key SHALL be send-only: it SHALL reach only the routes that add chat messages and saves, and SHALL NOT list, read, change or delete notes, health, places, recordings or chats. A phone key SHALL NOT add chats.

#### Scenario: A chat key sends a chat
- **WHEN** an unrevoked chat key sends new messages for a chat
- **THEN** Relay stores them and answers only with how many messages that chat now holds

#### Scenario: A chat key tries to read
- **WHEN** a chat key asks for the timeline, a recording, a summary, the chat list or one chat
- **THEN** Relay refuses it with 403 and returns no data

#### Scenario: A chat key tries to delete or change a chat
- **WHEN** a chat key asks to delete a chat, or sends a chat again with another title or other text for stored messages
- **THEN** Relay deletes nothing and keeps the stored title and messages
