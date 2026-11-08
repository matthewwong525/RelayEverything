## REMOVED Requirements

### Requirement: The app opens on Home

**Reason**: Home no longer has a *Connections* section.
**Migration**: Replaced by *Home holds the notes folders and the phone's data*. Sending, AI apps and webhooks move to the Account page in Settings.

### Requirement: Connections show what the person connected once signed in

**Reason**: The connections move from Home to the Account page in Settings.
**Migration**: Replaced by *The Account page shows the connection*.

### Requirement: Each kind of phone data has its own folder

**Reason**: A folder with sending off now asks the person to sign in, not to turn on sending.
**Migration**: Replaced by *Each kind of phone data has its own folder that asks to sign in*.

### Requirement: Home writes, talks, searches and opens Settings

**Reason**: *Open your Relay Everything page* moves from the *Sending* page to the Account page.
**Migration**: Replaced by *Home writes, talks, searches and opens Settings in one tap*.

### Requirement: Settings holds appearance, notes and voice settings

**Reason**: Settings now opens on an Account row.
**Migration**: Replaced by *Settings opens on the account*.

## ADDED Requirements

### Requirement: Home holds the notes folders and the phone's data

The phone app SHALL open on a *Home* screen with two groups of folders: the notes folders *Notes*, *Voice notes* and *Shares*; and *On this phone*, with *Location*, *Health*, *Calendar* and *Photos*. Home SHALL have no *Connections* section and no row for sending, AI apps or webhooks. Each notes folder SHALL show how many notes it holds. *Notes* SHALL hold every note, *Voice notes* only voice notes, and *Shares* only notes with a photo, a file or a link. Home SHALL show no folder for a feature that does not work yet. A person SHALL be able to fold *On this phone*, and the phone SHALL remember it. A tap on a section name SHALL fold or open it with no highlight behind the name, as in Apple Notes.

#### Scenario: Opening the app

- **WHEN** the person opens the app with 3 typed notes, 2 voice notes and 1 note with a photo
- **THEN** Home shows *Notes* 6, *Voice notes* 2 and *Shares* 1, *On this phone* below them, and no *Connections* section

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

### Requirement: Settings opens on the account

Settings SHALL show an Account row first, then *Appearance*, *Pin notes to where I am*, the speech model, and at the bottom the app's version and build number. Signed in to a Relay Everything server, the row SHALL show the account's email and the server. With sending to the person's own webhook, it SHALL say *My own webhook* and the webhook's address. Otherwise it SHALL say *Sign in to Relay Everything* and that notes stay on the phone until the person signs in. Health, the calendar, location history and photos SHALL NOT be in Settings.

#### Scenario: Signed out

- **WHEN** the person opens Settings on a new install
- **THEN** the first row says *Sign in to Relay Everything*, then the *Appearance*, *Notes* and *Voice notes* groups and the version, and no request leaves the phone

#### Scenario: Signed in

- **WHEN** the person signed in as you@example.com on app.relayeverything.com and opens Settings
- **THEN** the first row shows you@example.com and app.relayeverything.com, and a tap opens the Account page

### Requirement: The Account page shows the connection

Signed in to a Relay Everything server, the Account page SHALL show the account's email and server, *AI apps* and *Webhooks* with the names the server last gave, *Open your Relay Everything page*, the server to change, and *Sign out*. A tap on *AI apps* or *Webhooks* SHALL open that part of the person's Relay Everything page. *Sign out* SHALL ask first, then remove the phone's key and stop sending; notes from this phone SHALL stay on it. With sending to the person's own webhook, the page SHALL show its address, *Send a test* and *Stop sending*, and SHALL show no AI apps or webhooks list. The phone SHALL ask the server for the names and email only while it sends to a Relay Everything server.

#### Scenario: Signed in with connections

- **WHEN** the phone sends to a Relay Everything server and the person connected Claude and two webhooks
- **THEN** the Account page shows *AI apps* with *Claude*, *Webhooks* with both names and 2, and a tap on *Webhooks* opens the webhooks part of the person's page in the browser

#### Scenario: Signing out

- **WHEN** the person taps *Sign out* and confirms
- **THEN** the phone forgets its key, sending stops, the notes written on this phone stay, and Settings shows *Sign in to Relay Everything*
