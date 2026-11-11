# relay-home-screen Specification

## Purpose
The phone app opens on Home: the notes folders and a folder for each kind of phone data, with search, *New note* and a Settings button; Settings opens on the account.

## Requirements

### Requirement: Home holds the notes folders and the phone's data

The phone app SHALL open on a *Home* screen with three groups of folders: the notes folders *Notes*, *Voice notes* and *Shares*; *On this phone*, with *Location*, *Health*, *Calendar* and *Photos*; and *Other connections*, with *Connect your AI* and *Email notes*, in that order. Each row in *Other connections* SHALL carry one line that says what it does. Home SHALL have no *Connections* section and no row for sending or webhooks. Each notes folder SHALL show how many notes it holds. *Notes* SHALL hold every note, *Voice notes* only voice notes, and *Shares* only notes with a photo, a file or a link. Home SHALL show no folder for a feature that does not work yet. A person SHALL be able to fold *On this phone* and *Other connections*, and the phone SHALL remember it. A tap on a section name SHALL fold or open it with no highlight behind the name, as in Apple Notes.

#### Scenario: Opening the app

- **WHEN** the person opens the app with 3 typed notes, 2 voice notes and 1 note with a photo
- **THEN** Home shows *Notes* 6, *Voice notes* 2 and *Shares* 1, *On this phone* below them, then *Other connections* with *Connect your AI* and *Email notes*, each with its line, and no *Connections* section

#### Scenario: A first open

- **WHEN** a new install opens with sending off
- **THEN** Home shows every notes folder at 0 and *Location*, *Health*, *Calendar* and *Photos* as *Off*, and no request leaves the phone

### Requirement: Each kind of phone data has its own folder that asks to sign in

*Location*, *Health*, *Calendar* and *Photos* SHALL each open a page with that data's switch. Each row on Home SHALL say *Off*, or its status while on. The phone SHALL keep no new copy of places, readings or events to show them. While sending is off, each folder SHALL say it works once the person signs in, and SHALL offer one *Sign in* button that opens the same sign-in as the Account row.

#### Scenario: A folder with sending off

- **WHEN** sending is off and the person opens *Health*
- **THEN** the switch can not be turned on, the page says Health works once you sign in, and *Sign in* opens the sign-in

### Requirement: Home writes, talks, searches and opens Settings in one tap

Home SHALL have the one *New note* button, which writes on a tap and talks on a hold, and a search field that finds notes in every folder on the phone only. At the top right, Home SHALL have one Settings button that opens Settings in one tap, and no ⋯ menu. A voice note started from Shortcuts SHALL record whatever page is open.

#### Scenario: Settings in one tap

- **WHEN** the person taps the Settings button on Home
- **THEN** Settings opens, with no menu first

### Requirement: Sync now sits beside the sync state

While sending is on, the sync state under the title of Home and of each notes folder SHALL have a *Sync now* button right after it, which does the same as pulling the page down. With sending off, the button SHALL NOT show.

#### Scenario: Sync from Home

- **WHEN** sending is on, one note waits, and the person taps *Sync now* beside *1 waiting*
- **THEN** the phone syncs as a pull down does, and the state shows *Syncing*, then *Synced*

#### Scenario: Sending off

- **WHEN** sending is off
- **THEN** the line says *On this phone*, with no *Sync now* button

### Requirement: AI chat transcripts says how to save AI chats

*AI chat transcripts* SHALL open a page that says the plugin saves Claude Code and Codex chats word for word, and gives the steps to install it and connect a computer. Signed in to a Relay Everything server, the page SHALL link to the saved chats on that server's web page; otherwise it SHALL show no link. The page SHALL make no network call, and the phone's key SHALL still read no chat.

#### Scenario: Open it signed out
- **WHEN** a person with sending off taps *AI chat transcripts*
- **THEN** the page shows the steps, no link to chats, and no request leaves the phone

#### Scenario: Open it signed in
- **WHEN** a person signed in to Relay Everything taps *AI chat transcripts*, then the link
- **THEN** the browser opens the saved chats on their Relay Everything web page

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
