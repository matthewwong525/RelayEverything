# relay-web-app Specification

## Purpose

Relay Everything's web page is the Flutter phone app, built for the browser and sized for the window: notes written in the browser, the phone's connections in the left bar, and Settings in a dialog.

## Requirements

### Requirement: The layout fits the window

In a window at least 1,000 px wide the app SHALL show three panes: folders, the open folder's notes, and the open note. Between 700 and 1,000 px it SHALL show the notes and the open note, with the folders in a menu. Under 700 px it SHALL show the phone layout, one page at a time. A change of window size SHALL keep the open note and any words not yet saved. In the two wide layouts, one bar SHALL run along the top with the new-note button, *Text styles*, *Checklist*, *Table* and *Attach*, Share and search at its right end, and nothing SHALL sit at the bottom of the window. *Text styles* SHALL open a menu under its button, as Notes on a Mac has it: bold, italic, underline, strikethrough, the highlight pen and the colour at the top; then Title, Heading, Subheading, Body, Monostyled, Bulleted List, Dashed List and Numbered List, each in its own look with a ✓ at the current one; then Block Quote. A pick SHALL close the menu and leave the cursor in the note.

#### Scenario: A wide window
- **WHEN** a person opens the page in a 1,440 px wide window and taps a note
- **THEN** the note opens in the right pane, and the folders and the list stay in view

#### Scenario: Search from the top bar
- **WHEN** a person types a word in the search field at the top right
- **THEN** the list shows only the notes with that word, and the open note stays open

#### Scenario: The window gets narrow while a note is open
- **WHEN** a person types in a note and narrows the window to 600 px
- **THEN** the same note stays open as a full page, with every word typed

#### Scenario: A heading from the Aa menu
- **WHEN** a person clicks *Text styles* and then *Heading*
- **THEN** the menu closes, the cursor's line shows as a heading, and typing goes on in the note

### Requirement: A person writes, changes and deletes notes in the browser

A signed-in person SHALL be able to add a note, change its words and styles, add files to it, and delete it with *Undo*, from the browser, as on the phone. The server SHALL keep such a note in the person's space under a *Web* device of that space, which has no key. Each change SHALL reach the person's phones at their next sync, and their webhooks as a phone's change does. A change by the page's session SHALL come only from the page's own origin.

#### Scenario: A note written in the browser reaches the phone
- **WHEN** a person writes a note in the browser and their phone syncs
- **THEN** the phone shows the note, and each webhook gets one `note.created`

#### Scenario: A change from another site
- **WHEN** another website makes the person's browser send a note change with the session cookie
- **THEN** the server refuses it and nothing changes

### Requirement: The browser keeps no copy and records no voice

The browser app SHALL read notes from the person's space and SHALL keep no notes, keys or health data in the browser's storage. It SHALL NOT record voice notes; voice notes made on a phone SHALL play. The app SHALL name no ring: a note that came from a ring SHALL show as a plain note. It SHALL NOT show the phone's switches for health, places, the calendar, photos, the speech model or the phone's own webhook.

#### Scenario: Sign out on a shared computer
- **WHEN** a person signs out in the browser
- **THEN** the sign-in shows, and the browser keeps none of their notes

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

### Requirement: Keyboard and mouse work as on a computer

In the browser the app SHALL take keyboard shortcuts for a new note, search and delete, and the format keys of Notes on a Mac, with ⌘ on a Mac and Ctrl elsewhere: bold, italic, underline, strikethrough (⇧⌘X), highlight (⇧⌘E), Title, Heading, Subheading and Body (⇧⌘T, ⇧⌘H, ⇧⌘J, ⇧⌘B, and also ⌥⌘1, ⌥⌘2, ⌥⌘3, ⌥⌘0, as the browser keeps some of the others), Monostyled (⇧⌘M), the three lists (⇧⌘7, ⇧⌘8, ⇧⌘9), checklist (⇧⌘L), tick (⇧⌘U), block quote (⌘'), indent (⌘] and ⌘[, and Tab and Shift+Tab in a list), link (⌘K) and table (⌥⌘T). A right-click on selected words SHALL offer *Bold*, *Italic*, *Underline*, *Strikethrough*, *Highlight* and *Link…* with the usual cut, copy and paste. The app SHALL take files dropped onto an open note. Text SHALL be selectable and copyable.

#### Scenario: Drop a file on a note
- **WHEN** a person drags a PDF from their computer onto the open note
- **THEN** the file is added to the note, as with the paperclip

#### Scenario: A heading from the keyboard in Chrome
- **WHEN** a person on Windows presses Ctrl+Alt+2 on a line
- **THEN** the line shows as a heading, and the browser opens no new tab or window

### Requirement: The web page is the Flutter app, at the server's top address

Relay Everything's web page SHALL be the same Flutter app as the phone app, built for the browser. On the shared server and on a self-hosted server it SHALL open at the server's top address, `/`, with no login but the server's own sign-in. A sign-in with Apple or Google, a phone's connect and an AI app's connect SHALL come back to the app at that address. The company app SHALL NOT serve the page; its *Relay Everything* card SHALL link to the shared server. No part of the earlier page SHALL stay as a separate page.

#### Scenario: The top address opens the app
- **WHEN** a person with no sign-in opens `https://app.relayeverything.com/`
- **THEN** the app's own sign-in shows at that address, with no company login and no move to another path

#### Scenario: A sign-in comes back to the top address
- **WHEN** a person signs in with Google from `https://app.relayeverything.com/`
- **THEN** the browser comes back to `https://app.relayeverything.com/` signed in, with their notes
