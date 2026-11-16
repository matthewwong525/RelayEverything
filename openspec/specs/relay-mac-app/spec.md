# relay-mac-app Specification

## Purpose
The Relay Everything Mac app: a native app for macOS that keeps the person's notes on the Mac, works offline, syncs with their Relay Everything space when signed in, and is downloaded signed from the website.

## Requirements

### Requirement: The Mac app shows the computer page's layout

The Mac app SHALL open in its own window with the same layout as the computer page for the same window width: three parts from 1,000 px, two parts from 700 px, and the phone layout below. Its left bar SHALL show *Notes*, then *Connect your AI* and *Email notes* under *Other connections*, and *Settings* at its bottom. It SHALL NOT show Location, Health, Calendar or Photos.

#### Scenario: A wide window

- **WHEN** the person opens the Mac app in a window 1,200 px wide
- **THEN** it shows the left bar, the notes by day, and the open note side by side

#### Scenario: No phone-only folders

- **WHEN** the person looks at the left bar on the Mac
- **THEN** it has no Location, Health, Calendar or Photos row

### Requirement: The Mac keeps notes and works offline

The Mac app SHALL keep every note on the Mac, as the phone app does. Signed out, it SHALL make no network call, and the person SHALL still add, change, pin and delete notes. Signed in, each note SHALL go to the person's space, and notes from their other devices SHALL come to the Mac. A change made with no connection SHALL wait on the Mac and go when the Mac is online again, and SHALL NOT be lost when the app quits.

#### Scenario: Write with no connection

- **WHEN** a signed-in person writes a note with Wi-Fi off, quits the app, opens it again, and turns Wi-Fi on
- **THEN** the note is still on the Mac, and it reaches their space and their phone

#### Scenario: Signed out

- **WHEN** the person uses the Mac app without signing in
- **THEN** their notes stay only on the Mac, and the app makes no network call

### Requirement: The Mac signs in with its own key

The Mac app SHALL sign in only to Relay Everything, through the same sign-in and confirm step as a phone, or SHALL send to the person's own webhook with no account. The Mac SHALL get its own key, kept in the Mac's keychain, with no more reach than a phone's key. The key SHALL show among the person's devices under the Mac's name, and signing it out on another device or on the page SHALL stop the Mac at its next request.

#### Scenario: Sign in

- **WHEN** the person clicks *Sign in to Relay Everything* in Settings, signs in, and confirms
- **THEN** the Mac gets its own key, its notes start to sync, and the Mac shows on the person's phone among their devices

#### Scenario: Signed out from a phone

- **WHEN** the person signs out the Mac from their phone
- **THEN** the Mac's next request is refused, it stops sending, and its notes stay on the Mac

### Requirement: The Mac sends no private phone data

The Mac app SHALL NOT read or send health, location, calendar or photo data, and SHALL NOT ask the Mac for those permissions. It SHALL NOT record or play voice notes; a voice note made on a phone SHALL show its words.

#### Scenario: A voice note from the phone

- **WHEN** the person opens a voice note recorded on their phone
- **THEN** the Mac shows the note's words, and it shows no button to record or play a voice note

### Requirement: The Mac app works with a keyboard, a mouse and Finder

The Mac app SHALL have a Mac menu bar with *New Note* (⌘N), *Find* (⌘F) and *Settings* (⌘,), and a *Format* menu with every format item of the note page and its key, the same keys as Notes on a Mac and as the browser takes: bold (⌘B), italic (⌘I), underline (⌘U), strikethrough (⇧⌘X), highlight (⇧⌘E), Title, Heading, Subheading, Body and Monostyled (⇧⌘T, ⇧⌘H, ⇧⌘J, ⇧⌘B, ⇧⌘M), the three lists (⇧⌘7, ⇧⌘8, ⇧⌘9), checklist (⇧⌘L), block quote (⌘'), indent (⌘], ⌘[), link (⌘K) and table (⌥⌘T). A file dropped from Finder onto an open note SHALL be added to that note. A link SHALL open in the person's default browser, and a file on a note SHALL open in its Mac app. Parts that live only on the Relay Everything page, such as webhooks, saved chats and deleting the account, SHALL open that page in the browser.

#### Scenario: New note from the keyboard

- **WHEN** the person presses ⌘N
- **THEN** a new, empty note opens with the cursor in it

#### Scenario: Drop a file

- **WHEN** the person drops a PDF from Finder onto an open note
- **THEN** the PDF is added to that note and syncs with it

#### Scenario: A title from the Format menu

- **WHEN** the person picks *Format* → *Title* in the menu bar, or presses ⇧⌘T
- **THEN** the cursor's line shows as a Title

### Requirement: The Mac app is a signed download

Each pull request that changes `mobile/` SHALL build the Mac app, sending nothing. A build on `main` and a release SHALL sign the Mac app with a Developer ID certificate, have Apple check it, and put it, as one disk image for Apple silicon and Intel Macs, on that build's GitHub release beside the Android app. The website SHALL link to the newest released Mac app. A release SHALL NOT publish a Mac app that is unsigned or that Apple did not accept.

#### Scenario: Open a download

- **WHEN** the person downloads the Mac app from the website and opens it
- **THEN** macOS opens it with no warning that the developer cannot be checked

#### Scenario: Apple refuses the app

- **WHEN** Apple's check refuses the signed Mac app on a release
- **THEN** the release puts no Mac app on the GitHub release, and the run fails and says why
