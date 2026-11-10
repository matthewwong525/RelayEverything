# Spec Delta

## MODIFIED Requirements

### Requirement: The left bar matches the phone's Home

In the three-pane layout the left bar SHALL list the phone's notes folders, then a section named *Other connections* with Location, Health, Calendar, Photos, Connect your AI and Email notes, and SHALL end with *Settings* at its bottom. The page each of Connect your AI and Email notes opens SHALL say, at its top, what it does, as the phone's row does in its second line. It SHALL show no summary of the day. Until a later change shows that data, Location, Health, Calendar and Photos SHALL open a page that says the phone sends it and links to the app stores. Connect your AI SHALL hold the same two parts as on the phone; each computer and each AI app SHALL have *Disconnect*, after a confirm, and *Saved chats* SHALL open the person's saved chats from Claude Code and Codex, each naming its app. Email notes SHALL show both notes addresses with *Copy*, and *New address* for the private one. A link to `#ai-apps`, `#email-notes` or `#chats` SHALL open the matching page.

#### Scenario: Open Health in the browser
- **WHEN** a person clicks *Health* in the left bar
- **THEN** a page says their phone sends health data and shows the links to the app for iPhone and Android, and no health data shows

#### Scenario: Read a saved chat
- **WHEN** a person clicks *Connect your AI*, then *Saved chats*, then a chat
- **THEN** the chat and its saves show, as on the earlier page

#### Scenario: Disconnect a computer
- **WHEN** a person clicks *Disconnect* beside their old laptop in *Connect your AI*, and confirms
- **THEN** the laptop leaves the list and stops saving chats, and the notes stay open in the window

## REMOVED Requirements

### Requirement: Settings opens as a dialog with every page of the old Settings
**Reason**: Settings in the browser now has the same rows as the phone, and AI apps and email notes moved to the left bar.
**Migration**: See `relay-settings`; the dialog stays, with Account (phones, then *Advanced* with API keys and webhooks) and Appearance. A link to `#account`, `#devices` or `#webhooks` opens Account; computers and AI apps move to *Connect your AI*.
