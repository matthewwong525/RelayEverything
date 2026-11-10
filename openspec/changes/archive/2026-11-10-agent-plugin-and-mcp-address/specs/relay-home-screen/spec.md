# Spec Delta

## MODIFIED Requirements

### Requirement: Home holds the notes folders and the phone's data

The phone app SHALL open on a *Home* screen with three groups of folders: the notes folders *Notes*, *Voice notes* and *Shares*; *On this phone*, with *Location*, *Health*, *Calendar* and *Photos*; and *Other connections*, with *AI chat transcripts*. Home SHALL have no *Connections* section and no row for sending, AI apps or webhooks. Each notes folder SHALL show how many notes it holds. *Notes* SHALL hold every note, *Voice notes* only voice notes, and *Shares* only notes with a photo, a file or a link. Home SHALL show no folder for a feature that does not work yet. A person SHALL be able to fold *On this phone* and *Other connections*, and the phone SHALL remember it. A tap on a section name SHALL fold or open it with no highlight behind the name, as in Apple Notes.

#### Scenario: Opening the app

- **WHEN** the person opens the app with 3 typed notes, 2 voice notes and 1 note with a photo
- **THEN** Home shows *Notes* 6, *Voice notes* 2 and *Shares* 1, *On this phone* and *Other connections* below them, and no *Connections* section

#### Scenario: A first open

- **WHEN** a new install opens with sending off
- **THEN** Home shows every notes folder at 0 and *Location*, *Health*, *Calendar* and *Photos* as *Off*, and no request leaves the phone

## ADDED Requirements

### Requirement: AI chat transcripts says how to save AI chats

*AI chat transcripts* SHALL open a page that says the plugin saves Claude Code and Codex chats word for word, and gives the steps to install it and connect a computer. Signed in to a Relay Everything server, the page SHALL link to the saved chats on that server's web page; otherwise it SHALL show no link. The page SHALL make no network call, and the phone's key SHALL still read no chat.

#### Scenario: Open it signed out
- **WHEN** a person with sending off taps *AI chat transcripts*
- **THEN** the page shows the steps, no link to chats, and no request leaves the phone

#### Scenario: Open it signed in
- **WHEN** a person signed in to Relay Everything taps *AI chat transcripts*, then the link
- **THEN** the browser opens the saved chats on their Relay Everything web page
