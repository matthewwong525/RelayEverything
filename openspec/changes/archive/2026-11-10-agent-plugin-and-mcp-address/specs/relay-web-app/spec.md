# Spec Delta

## MODIFIED Requirements

### Requirement: The left bar matches the phone's Home

In the three-pane layout the left bar SHALL list the phone's notes folders, then a section named *Other connections* with Location, Health, Calendar, Photos and AI chat transcripts, and SHALL end with *Settings* at its bottom. It SHALL show no summary of the day. Until a later change shows that data, Location, Health, Calendar and Photos SHALL open a page that says the phone sends it and links to the app stores. AI chat transcripts SHALL open the person's saved chats from Claude Code and Codex, each naming its app.

#### Scenario: Open Health in the browser
- **WHEN** a person clicks *Health* in the left bar
- **THEN** a page says their phone sends health data and shows the links to the app for iPhone and Android, and no health data shows

#### Scenario: Read a saved chat
- **WHEN** a person clicks *AI chat transcripts* and then a chat
- **THEN** the chat and its saves show, as on the earlier page
