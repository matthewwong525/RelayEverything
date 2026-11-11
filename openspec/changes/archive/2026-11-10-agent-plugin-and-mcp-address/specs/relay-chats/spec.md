# Spec Delta

## MODIFIED Requirements

### Requirement: A chat key reaches only the chat routes
Relay SHALL accept saved chats only from an unrevoked chat key or computer key. A chat key SHALL be send-only: it SHALL reach only the routes that add chat messages and saves, and SHALL NOT list, read, change or delete notes, health, places, recordings or chats. A computer key SHALL reach the same chat routes, and SHALL NOT change or delete a chat. A phone key SHALL NOT add chats.

#### Scenario: A chat key sends a chat
- **WHEN** an unrevoked chat key sends new messages for a chat
- **THEN** Relay stores them and answers only with how many messages that chat now holds

#### Scenario: A chat key tries to read
- **WHEN** a chat key asks for the timeline, a recording, a summary, the chat list or one chat
- **THEN** Relay refuses it with 403 and returns no data

#### Scenario: A chat key tries to delete or change a chat
- **WHEN** a chat key asks to delete a chat, or sends a chat again with another title or other text for stored messages
- **THEN** Relay deletes nothing and keeps the stored title and messages

## ADDED Requirements

### Requirement: A chat names the app it came from
Each saved chat SHALL keep the app it came from, Claude Code or Codex, as its first send named it. A chat sent with no app SHALL count as from Claude Code. The page, the web API and the AI connector SHALL show the app with each chat.

#### Scenario: A Codex chat
- **WHEN** a computer sends a chat named as from Codex
- **THEN** the page's list shows that chat as from Codex
