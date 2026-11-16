## ADDED Requirements

### Requirement: The Mac app opens to its notes

The Mac app SHALL show its notes window on every open: on the first open with no saved key, and on each open with a saved key or webhook. A key or webhook saved on the Mac SHALL be read back on the next open. Reading the Mac's keychain SHALL NOT stop the app before its first screen.

#### Scenario: First open

- **WHEN** the person opens the Mac app for the first time, with nothing saved in the keychain
- **THEN** the window shows the notes list, signed out, not a black window

#### Scenario: Open after sign-in

- **WHEN** the person signed in on the Mac, quits the app and opens it again
- **THEN** the window shows the notes list, still signed in with the same key

### Requirement: The Mac download opens as a Relay Everything install window

The Mac disk image SHALL open as a fixed-size Finder window with no toolbar or sidebar, on a background in the Relay Everything brand: the logo, the app and Applications on a deep emerald band with an arrow from the app to Applications, and the words *Drag Relay Everything to Applications*. The band color SHALL give the names under the icons a contrast of 4.5 to 1 or more with both white and black text, so they read in light and dark mode. The disk SHALL show the Relay Everything icon. A pull request's unsigned Mac build SHALL be the same disk image.

#### Scenario: Open the download

- **WHEN** the person opens `Relay-Everything-Mac.dmg`
- **THEN** Finder shows the branded window with the app on the left and Applications on the right, and dragging the app onto Applications installs it

#### Scenario: Dark mode

- **WHEN** the person's Mac is in dark mode and opens the download
- **THEN** the names *Relay Everything* and *Applications* read clearly on the emerald band
