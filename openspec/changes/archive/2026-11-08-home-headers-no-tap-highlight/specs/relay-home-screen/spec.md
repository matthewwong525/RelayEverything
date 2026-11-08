## MODIFIED Requirements

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
