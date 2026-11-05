# Spec Delta

## Purpose
A Claude Code plugin, safe to publish, that saves the owner's Claude Code chats to their Relay server word for word, with a save tool, a per-project off switch, and an optional link to the Relay AI connector.

## ADDED Requirements

### Requirement: Chats are sent as they happen
With a connect code entered, the plugin SHALL send each Claude Code chat's new messages to Relay after each reply and when the chat ends, without making Claude Code wait. A send that fails SHALL be tried again at the next session start. Messages already stored SHALL NOT be sent again. A chat with no typed message SHALL NOT be sent.

#### Scenario: A reply finishes
- **WHEN** the AI finishes a reply in a project where saving is on
- **THEN** Relay holds every message of the chat so far, once each

#### Scenario: The computer is offline
- **WHEN** a send fails because Relay can't be reached
- **THEN** the chat is sent at the next Claude Code start, and no message is lost or doubled

### Requirement: A saved chat keeps messages exact and steps short
The plugin SHALL send the person's messages and the AI's replies word for word, and each tool step as one short line that names what was done. It SHALL NOT send tool output, file contents, or the AI's private reasoning. Before any text leaves the computer, the plugin SHALL replace key-shaped text, and the project's own `.env` values, with a hidden marker.

#### Scenario: The AI runs a command
- **WHEN** the AI runs a command and reads its output
- **THEN** Relay gets one step line naming the command, and none of its output

#### Scenario: A key is pasted into the chat
- **WHEN** a message holds text shaped like an API key or a value from the project's `.env`
- **THEN** Relay gets the message with that text hidden

### Requirement: Saving can be turned off per project
Saving SHALL be on in every project until the person turns it off there. With saving off, neither the hooks nor the save tool SHALL send anything from that project, and the save tool SHALL say how to turn it on. The person SHALL be able to see whether saving is on and when the project last sent.

#### Scenario: Saving is off
- **WHEN** the person turns saving off in a project and then chats there
- **THEN** nothing from that project reaches Relay

### Requirement: The AI can save on request
The plugin SHALL offer a save tool that sends the current chat so far and a title and summary the AI writes, marked as written by the AI.

#### Scenario: The person asks to save
- **WHEN** the person asks the AI to save the chat to Relay
- **THEN** Relay holds the chat so far and the AI's summary on that chat, and the AI says it was saved

### Requirement: The plugin holds no key or address
The plugin's files SHALL hold no key and no Relay address. The connect code SHALL be kept in Claude Code's secure store and SHALL NOT be written to a log, a file in a project, or a chat.

#### Scenario: A key or address is added to the plugin
- **WHEN** a file in the plugin holds text shaped like a key, a Relay address, or an email
- **THEN** the plugin's checks fail before it can be published

### Requirement: The plugin can add the AI connector
The plugin SHALL add the Relay AI connector to Claude Code when the person gives its address, so the AI can read Relay in later chats after one sign-in.

#### Scenario: The person adds the connector
- **WHEN** the person gives the address shown on the Relay page's *Your AI* card
- **THEN** Claude Code lists the Relay connector and asks for the Relay sign-in on first use

### Requirement: The plugin sends to the server that made its connect code
The plugin SHALL send chats and saves only to the Relay server named in its connect code, whether Relay's or one the person runs, and SHALL work the same with either. The plugin's own page, the Relay website's Claude Code page and the Relay page's connect dialog SHALL say that a person can run their own Relay server to keep chats in their own account.

#### Scenario: A connect code from a person's own server
- **WHEN** the person enters a connect code made on a Relay server they run
- **THEN** their chats go to that server, and nothing goes to Relay's server
