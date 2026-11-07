# relay-chats Specification

## Purpose
Relay's server keeps the owner's AI chats beside their notes: it takes chats from a key that can only send chats, shows them on the Relay page, and lets the owner's AI connector read them.

## Requirements

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

### Requirement: Chats are stored once, in order
Relay SHALL keep one chat per key and session, and each message once by its position in the chat. A message sent again SHALL NOT be stored twice, and the answer SHALL say how many messages are stored, so the sender can send only what is missing. A message's text SHALL be stored exactly as sent.

#### Scenario: The same messages arrive twice
- **WHEN** a send repeats messages Relay already holds for that chat
- **THEN** Relay keeps one copy of each and answers with the same count as before

#### Scenario: A send is too large
- **WHEN** one send holds more messages or bytes than the stated cap
- **THEN** Relay refuses the whole send with 413 and stores none of it

### Requirement: A save keeps the AI's summary apart from the chat
Relay SHALL store a save's title and text on its chat, marked as written by the AI, and SHALL keep the chat's own messages unchanged. The Relay page and the AI connector SHALL show the newest save's title as the chat's title.

#### Scenario: The AI saves a summary
- **WHEN** a chat key sends a save with a title and a summary for a chat
- **THEN** the chat shows that title, and its summary shows as written by the AI above the messages

### Requirement: The owner reads, searches and deletes chats on the Relay page
The Relay page SHALL list saved chats newest first, with title, project, time and message count, and SHALL find chats whose messages or saves hold every word of a search. Opening a chat SHALL show its saves and its messages in order, marking each as yours, the AI's, or a step. Deleting a chat SHALL remove its messages and saves, after a confirm that says it can't be undone.

#### Scenario: Search finds a chat
- **WHEN** the owner searches for words that appear in one chat's messages
- **THEN** the list shows that chat and not chats without those words

#### Scenario: The owner deletes a chat
- **WHEN** the owner confirms *Delete* on a chat
- **THEN** the chat, its messages and its saves are gone from the page, from search and from the AI connector

### Requirement: The AI connector can read chats
The owner's AI connector SHALL offer two read-only tools: one that searches chats by words and time and returns matching chats with the matching lines, and one that returns one chat's saves and messages a part at a time. Neither tool SHALL change data or return a device's id.

#### Scenario: The AI searches chats
- **WHEN** a connected AI app searches chats for a word that appears in one chat
- **THEN** it gets that chat's id, title, project, time and the matching lines

#### Scenario: A long chat is read in parts
- **WHEN** the AI reads a chat longer than one part
- **THEN** it gets the first part and a cursor that returns the next part
