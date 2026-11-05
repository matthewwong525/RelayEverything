# relay-ai-connector Specification

## Purpose
Let Matthew ask any AI chat app about his Relay notes, health and places through one connector address, read-only, admitting only him.

## Requirements

### Requirement: One address connects any AI chat app

Relay SHALL offer one remote MCP connector address that a chat app supporting remote MCP with OAuth (the Claude app, Claude Desktop, ChatGPT, Claude Code) can connect to after a single sign-in, with no key typed or pasted.

#### Scenario: Connecting the Claude app
- **WHEN** Matthew adds the connector address in the Claude app and approves the Relay sign-in
- **THEN** the app lists Relay's tools and a chat can answer "what did I note yesterday?" from his notes

### Requirement: Only the owner can connect

The connector SHALL admit only a sign-in by the site's owner, and SHALL refuse every request that has no valid connector token, including one carrying a Relay device key or any other site login.

#### Scenario: Someone else signs in
- **WHEN** a person other than the owner completes the sign-in
- **THEN** no connection is made and no Relay data is returned

#### Scenario: A request with no token
- **WHEN** a request reaches the connector without a valid token
- **THEN** it is refused before any data is read

### Requirement: The AI reads but never changes

Every connector tool SHALL be marked read-only and SHALL only read notes, health samples and locations; no tool SHALL add, edit or delete any Relay data, and recordings SHALL NOT be returned.

#### Scenario: The AI is asked to delete a note
- **WHEN** a chat asks the AI to delete or edit a Relay note
- **THEN** no connector tool can do it and the note stays as it is

### Requirement: Answers are bounded to the question

Each tool SHALL return only rows inside the time range or search it was asked for, capped in count, with a way to page for more.

#### Scenario: A month of health
- **WHEN** the AI asks for sleep across a month
- **THEN** it gets one value per night for that month, not the raw samples of every other type

### Requirement: The owner sees and removes connected apps

The Relay page SHALL list each connected AI app with when it connected, and removing one SHALL stop that app at its next request while other connected apps keep working.

#### Scenario: Disconnecting ChatGPT
- **WHEN** Matthew presses Disconnect beside ChatGPT
- **THEN** ChatGPT's next question to Relay is refused and the Claude app still answers
