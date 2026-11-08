# relay-home-screen Specification

## Purpose
The phone app opens on Home: the notes folders, a folder for each kind of phone data, and what the person connected, with search, *New note* and the ⋯ menu.

## Requirements

### Requirement: The app opens on Home

The phone app SHALL open on a *Home* screen with three groups of folders: the notes folders *Notes*, *Voice notes* and *Shares*; *On this phone*, with *Location*, *Health* and *Calendar*; and *Connections*, with *Sending*, *AI apps* and *Webhooks*. Each notes folder SHALL show how many notes it holds. *Notes* SHALL hold every note, *Voice notes* only voice notes, and *Shares* only notes with a photo, a file or a link. Home SHALL show no folder for a feature that does not work yet. A person SHALL be able to fold *On this phone* and *Connections*, and the phone SHALL remember it. A tap on a section name SHALL fold or open it with no highlight behind the name, as in Apple Notes.

#### Scenario: Opening the app

- **WHEN** the person opens the app with 3 typed notes, 2 voice notes and 1 note with a photo
- **THEN** Home shows *Notes* 6, *Voice notes* 2 and *Shares* 1, and a tap on *Voice notes* lists only the 2 voice notes

#### Scenario: A first open

- **WHEN** a new install opens with sending off
- **THEN** Home shows every notes folder at 0, *Location*, *Health*, *Calendar* and *Sending* as *Off*, and no request leaves the phone

#### Scenario: Folding a section with no highlight

- **WHEN** the person taps *Connections* on Home
- **THEN** the section folds, its chevron turns, and no grey box shows behind the name

### Requirement: Home writes, talks, searches and holds the menu

Home SHALL have the one *New note* button, which writes on a tap and talks on a hold, as the notes screen requirements say, and a search field that finds notes in every folder on the phone only. Home SHALL have the ⋯ menu with *Settings*, and, while sending is on, *Sync now*, and *Open your Relay Everything page* when the phone sends to a Relay Everything server. A voice note started from Shortcuts SHALL record whatever page is open.

#### Scenario: Search from Home with no signal

- **WHEN** the phone has no connection and the person types *dentist* in *Search* on Home
- **THEN** the notes from every folder that hold *dentist* show, and no request leaves the phone

#### Scenario: The menu with sending off

- **WHEN** sending is off and the person opens the ⋯ menu
- **THEN** it shows *Settings* and no *Sync now* or page link

### Requirement: Each kind of phone data has its own folder

*Location*, *Health* and *Calendar* SHALL each open a page with that data's switch. Location SHALL also hold *Save battery* and *Every 100 m*, and Calendar the phone's calendars, each with its own switch. Each row on Home SHALL say *Off*, or its status while on. The phone SHALL keep no new copy of places, readings or events to show them. While sending is off, each folder SHALL say it works only with sending on, and SHALL offer one button that turns sending on in the same steps as before.

#### Scenario: Location from Home

- **WHEN** sending and location history are on, in *Save battery*, and the last point went at 14:05
- **THEN** the *Location* row says *Save battery · Sent 14:05*, and its page shows the switch, both modes, and that time

#### Scenario: A folder with sending off

- **WHEN** sending is off and the person opens *Health*
- **THEN** the switch can not be turned on, the page says Health works with sending on, and *Turn on sending* asks where to send

### Requirement: Connections show what the person connected once signed in

*Sending* SHALL say where the phone sends: *Off*, the Relay Everything server, or the person's own webhook, and its page SHALL hold the sending switch, the choice of place, the webhook test, the server, and *Disconnect this phone*. While the phone sends to a Relay Everything server, *AI apps* and *Webhooks* SHALL show the names of the person's connected AI apps and webhooks, as the server last answered, and a tap SHALL open that part of the person's Relay Everything page. Otherwise each SHALL say *Sign in to see*, and a tap SHALL open the screen that asks where to send. The phone SHALL ask the server for these names only while sending is on to a Relay Everything server.

#### Scenario: Signed in

- **WHEN** the phone sends to a Relay Everything server and the person connected Claude and two webhooks
- **THEN** *AI apps* shows *Claude* and *Webhooks* shows both names and 2, and a tap on *Webhooks* opens the webhooks part of the person's page in the browser

#### Scenario: Not signed in

- **WHEN** sending is off, or the phone sends to the person's own webhook
- **THEN** *AI apps* and *Webhooks* say *Sign in to see*, the phone asks the server nothing, and a tap opens the screen that asks where to send

### Requirement: Settings holds only notes and voice settings

Settings SHALL hold *Pin notes to where I am* and the speech model. Sending, health, the calendar and location history SHALL NOT be in Settings.

#### Scenario: Open Settings

- **WHEN** the person opens Settings from the ⋯ menu
- **THEN** it shows the *Notes* and *Voice notes* groups only
