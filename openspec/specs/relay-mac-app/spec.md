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

The Mac app SHALL NOT read or send health, location, calendar or photo data, and SHALL NOT ask the Mac for those permissions. It SHALL NOT record voice notes. A recording made on a phone SHALL show as its card with its transcript, and SHALL play from the person's space once the sound is there.

#### Scenario: A voice note from the phone

- **WHEN** the person opens a voice note recorded on their phone and sent with its recording
- **THEN** the Mac shows the recording's card with its transcript, play plays the recording, and the Mac shows no button to record

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

Each pull request that changes `mobile/` SHALL build the Mac app, sending nothing. A build on `main` and a release SHALL sign the Mac app with a Developer ID certificate, have Apple check it, and put it, as one disk image for Apple silicon and Intel Macs, on that build's GitHub release beside the Android app. The website SHALL link to the newest signed Mac app, test builds included, at one address that works before the first full release. A release SHALL NOT publish a Mac app that is unsigned or that Apple did not accept.

#### Scenario: Open a download

- **WHEN** the person downloads the Mac app from the website and opens it
- **THEN** macOS opens it with no warning that the developer cannot be checked

#### Scenario: Download before the first full release

- **WHEN** only test builds have a signed Mac app, and the person clicks *Download for Mac* on the website
- **THEN** they get the newest signed Mac app, not a "not found" page

#### Scenario: Apple refuses the app

- **WHEN** Apple's check refuses the signed Mac app on a release
- **THEN** the release puts no Mac app on the GitHub release, and the run fails and says why

### Requirement: The Mac app updates itself

The Mac app SHALL check for a newer version when it opens and then once a day, and when the person picks *Check for Updates…* in the app menu or in Settings. When it finds a newer version, it SHALL show what is new and install only after the person clicks *Install Update*, then open the new version. An update SHALL keep the person's notes, sign-in and settings. The app SHALL install an update only when the update's own signature matches the key built into the app.

#### Scenario: A new version is ready

- **WHEN** a newer full release exists and the person opens the Mac app
- **THEN** the update window shows the new version with *Install Update*, *Remind Me Later* and *Skip This Version*, and after *Install Update* the new version opens with the same notes and sign-in

#### Scenario: A changed update file

- **WHEN** the update file does not match its signature
- **THEN** the app does not install it and stays on its version

### Requirement: The person chooses test builds

The Mac app's Settings SHALL have a *Get test builds* switch, off by default. With it off, the app SHALL offer only full releases. With it on, the app SHALL also offer each new test build. The app SHALL NOT offer a version older than the one it has.

#### Scenario: Test builds off

- **WHEN** *Get test builds* is off and only a newer test build exists
- **THEN** the app offers no update

#### Scenario: Switch turned off on a test build

- **WHEN** the person turns *Get test builds* off while the app is a test build newer than the last full release
- **THEN** the app keeps its version and offers the next full release that is newer

### Requirement: The Mac app opens to its notes

The Mac app SHALL show its notes window on every open: on the first open with no saved key, and on each open with a saved key or webhook. A key or webhook saved on the Mac SHALL be read back on the next open. Reading the Mac's keychain SHALL NOT stop the app before its first screen.

#### Scenario: First open

- **WHEN** the person opens the Mac app for the first time, with nothing saved in the keychain
- **THEN** the window shows the notes list, signed out, not a black window

#### Scenario: Open after sign-in

- **WHEN** the person signed in on the Mac, quits the app and opens it again
- **THEN** the window shows the notes list, still signed in with the same key

### Requirement: The Mac download opens as a Relay Everything install window

The Mac disk image SHALL open as a fixed-size Finder window with no toolbar or sidebar, on a background in the Relay Everything brand: light paper with the logo, the app and Applications, an arrow from the app to Applications, and the words *Drag Relay Everything to Applications*. The background SHALL stay light behind the icons, so Finder writes their names in black, readable in light and dark mode, and the app's green icon stands out. The disk SHALL show the Relay Everything icon. A pull request's unsigned Mac build SHALL be the same disk image, and its app SHALL open on a Mac once the person allows it.

#### Scenario: Open the download

- **WHEN** the person opens `Relay-Everything-Mac.dmg`
- **THEN** Finder shows the branded window with the app on the left and Applications on the right, and dragging the app onto Applications installs it

#### Scenario: Dark mode

- **WHEN** the person's Mac is in dark mode and opens the download
- **THEN** the names *Relay Everything* and *Applications* read clearly, in black, and the app's icon stands out from the background
