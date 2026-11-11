## MODIFIED Requirements

### Requirement: The left bar matches the phone's Home

In the three-pane layout the left bar SHALL have one *Notes* row, as the phone's Home has, then a section named *Other connections* with Location, Health, Calendar, Photos, Connect your AI and Email notes, and SHALL end with *Settings* at its bottom. The page each of Connect your AI and Email notes opens SHALL say, at its top, what it does, as the phone's row does in its second line. It SHALL show no summary of the day. Until a later change shows that data, Location, Health, Calendar and Photos SHALL open a page that says the phone sends it and links to the app stores. Connect your AI SHALL hold the same two parts as on the phone; each computer and each AI app SHALL have *Disconnect*, after a confirm, and *Saved chats* SHALL open the person's saved chats from Claude Code and Codex, each naming its app. Email notes SHALL show both notes addresses with *Copy*, and *New address* for the private one. A link to `#ai-apps`, `#email-notes` or `#chats` SHALL open the matching page. The notes list SHALL have the phone's filters, *All*, *Voice* and *Photos and files*, and a voice note SHALL have the phone's voice player, with a plain line in place of the sound waves.

#### Scenario: Open Health in the browser
- **WHEN** a person clicks *Health* in the left bar
- **THEN** a page says their phone sends health data and shows the links to the app for iPhone and Android, and no health data shows

#### Scenario: Read a saved chat
- **WHEN** a person clicks *Connect your AI*, then *Saved chats*, then a chat
- **THEN** the chat and its saves show, as on the earlier page

#### Scenario: Disconnect a computer
- **WHEN** a person clicks *Disconnect* beside their old laptop in *Connect your AI*, and confirms
- **THEN** the laptop leaves the list and stops saving chats, and the notes stay open in the window

#### Scenario: Filter on a computer
- **WHEN** a person clicks *Notes* in the left bar and then *Voice*
- **THEN** only voice notes show, and the left bar has no *Voice notes* or *Shares* row
