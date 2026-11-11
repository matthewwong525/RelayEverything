## MODIFIED Requirements

### Requirement: The left bar matches the phone's Home

In the three-pane layout the left bar SHALL have one *Notes* row, as the phone's Home has, then a section named *Other connections* with Location, Health, Calendar, Photos and Claude Code chats, and SHALL end with *Settings* at its bottom. It SHALL show no summary of the day. Until a later change shows that data, Location, Health, Calendar and Photos SHALL open a page that says the phone sends it and links to the app stores. Claude Code chats SHALL open the person's saved chats, as the earlier page did. The notes list SHALL have the phone's filters, *All*, *Voice* and *Photos and files*, and a voice note SHALL have the phone's voice player, with a plain line in place of the sound waves.

#### Scenario: Open Health in the browser
- **WHEN** a person clicks *Health* in the left bar
- **THEN** a page says their phone sends health data and shows the links to the app for iPhone and Android, and no health data shows

#### Scenario: Read a saved chat
- **WHEN** a person clicks *Claude Code chats* and then a chat
- **THEN** the chat and its saves show, as on the earlier page

#### Scenario: Filter on a computer
- **WHEN** a person clicks *Notes* in the left bar and then *Voice*
- **THEN** only voice notes show, and the left bar has no *Voice notes* or *Shares* row
