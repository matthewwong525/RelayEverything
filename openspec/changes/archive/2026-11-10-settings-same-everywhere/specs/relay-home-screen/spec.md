# Spec Delta

## MODIFIED Requirements

### Requirement: Home holds the notes folders and the phone's data

The phone app SHALL open on a *Home* screen with three groups of folders: the notes folders *Notes*, *Voice notes* and *Shares*; *On this phone*, with *Location*, *Health*, *Calendar* and *Photos*; and *Other connections*, with *Connect your AI* and *Email notes*, in that order. Each row in *Other connections* SHALL carry one line that says what it does. Home SHALL have no *Connections* section and no row for sending or webhooks. Each notes folder SHALL show how many notes it holds. *Notes* SHALL hold every note, *Voice notes* only voice notes, and *Shares* only notes with a photo, a file or a link. Home SHALL show no folder for a feature that does not work yet. A person SHALL be able to fold *On this phone* and *Other connections*, and the phone SHALL remember it. A tap on a section name SHALL fold or open it with no highlight behind the name, as in Apple Notes.

#### Scenario: Opening the app

- **WHEN** the person opens the app with 3 typed notes, 2 voice notes and 1 note with a photo
- **THEN** Home shows *Notes* 6, *Voice notes* 2 and *Shares* 1, *On this phone* below them, then *Other connections* with *Connect your AI* and *Email notes*, each with its line, and no *Connections* section

#### Scenario: A first open

- **WHEN** a new install opens with sending off
- **THEN** Home shows every notes folder at 0 and *Location*, *Health*, *Calendar* and *Photos* as *Off*, and no request leaves the phone

## ADDED Requirements

### Requirement: Connect your AI and Email notes show what is connected

*Connect your AI* SHALL open a page with two parts. *Claude Code and Codex* SHALL list each of the person's computers with the plugin, with when it last saved a chat, then *Saved chats*, which opens the person's saved chats and says only the plugin saves them, and *Get the plugin*. *Claude, ChatGPT and other AI apps* SHALL show the AI connector's address to copy, and each connected AI app with the day it connected. On the phone, disconnecting a computer or an app SHALL open the person's Relay Everything page. *Email notes* SHALL open a page that says a mail sent or forwarded becomes a note, and, signed in, shows two addresses, each with *Copy*: the shared notes address, which takes mail only from the person's sign-in email, and their private address, which takes mail from anyone. Signed out, both pages SHALL make no network call, SHALL show no address but the AI connector's, and SHALL offer *Sign in*.

#### Scenario: Connect your AI, signed in
- **WHEN** a signed-in person with the plugin on their laptop and Claude connected opens *Connect your AI*
- **THEN** the page shows the laptop with its last saved chat, *Saved chats*, the address to copy, and *Claude* with the day it connected

#### Scenario: Email notes, signed in
- **WHEN** a signed-in person opens *Email notes*
- **THEN** the page shows the shared notes address, marked as taking mail only from their sign-in email, and their private address, marked as taking mail from anyone

#### Scenario: Email notes, signed out
- **WHEN** a person with sending off opens *Email notes*
- **THEN** the page says what email notes do, shows no address, offers *Sign in*, and no request leaves the phone

## REMOVED Requirements

### Requirement: Settings opens on the account
**Reason**: Settings is now one shape on the phone and the web.
**Migration**: See `relay-settings`: *Settings shows the same rows on the phone and the web* and *The account card says where notes go, in few words*.

### Requirement: The Account page shows the connection
**Reason**: The Account page no longer lists AI apps or webhooks or asks where private data goes.
**Migration**: AI apps and the plugin's computers move to *Connect your AI* on Home; webhooks and the private-data choice move to *Webhooks* under *Advanced* on the Account page; see `relay-settings`: *Account holds the person, their phones and the developer options* and *Advanced on the Account page holds the developer options*.
