## REMOVED Requirements

### Requirement: Home writes, talks, searches and holds the menu

**Reason**: Home's ⋯ menu becomes a Settings button, and *Sync now* and the page link move.
**Migration**: See *Home writes, talks, searches and opens Settings* below, and *Sync now sits beside the sync state*.

### Requirement: Settings holds only notes and voice settings

**Reason**: Settings gains *Appearance* and the app version.
**Migration**: See *Settings holds appearance, notes and voice settings* below.

## ADDED Requirements

### Requirement: Home writes, talks, searches and opens Settings

Home SHALL have the one *New note* button, which writes on a tap and talks on a hold, as the notes screen requirements say, and a search field that finds notes in every folder on the phone only. At the top right, Home SHALL have one Settings button that opens Settings in one tap, and no ⋯ menu. While the phone sends to a Relay Everything server, the *Sending* page SHALL offer *Open your Relay Everything page*, which opens the person's page in the browser. A voice note started from Shortcuts SHALL record whatever page is open.

#### Scenario: Settings in one tap

- **WHEN** the person taps the Settings button on Home
- **THEN** Settings opens, with no menu first

#### Scenario: The page link is on Sending

- **WHEN** the phone sends to a Relay Everything server and the person opens *Sending*
- **THEN** it shows *Open your Relay Everything page*, and a tap opens the person's page in the browser; with sending off or to the person's own webhook, it does not show

### Requirement: Sync now sits beside the sync state

While sending is on, the sync state under the title of Home and of each notes folder SHALL have a *Sync now* button right after it, which does the same as pulling the page down. With sending off, the button SHALL NOT show.

#### Scenario: Sync from Home

- **WHEN** sending is on, one note waits, and the person taps *Sync now* beside *1 waiting*
- **THEN** the phone syncs as a pull down does, and the state shows *Syncing*, then *Synced*

#### Scenario: Sending off

- **WHEN** sending is off
- **THEN** the line says *On this phone*, with no *Sync now* button

### Requirement: Settings holds appearance, notes and voice settings

Settings SHALL hold *Appearance*, *Pin notes to where I am* and the speech model, and at the bottom the app's version and build number. Sending, health, the calendar and location history SHALL NOT be in Settings.

#### Scenario: Open Settings

- **WHEN** the person opens Settings from Home
- **THEN** it shows the *Appearance*, *Notes* and *Voice notes* groups only, and the version and build, such as *Relay Everything 1.4.0 (91)*
