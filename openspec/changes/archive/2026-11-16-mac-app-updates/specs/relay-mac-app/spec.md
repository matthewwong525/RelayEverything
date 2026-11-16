## MODIFIED Requirements

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

## ADDED Requirements

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
