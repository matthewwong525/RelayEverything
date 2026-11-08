## MODIFIED Requirements

### Requirement: Tool bars match Apple Notes

While the keyboard is up, a tool bar SHALL float above it with *Text styles*, *Checklist* and *Attach*, and the top SHALL show back, share, ⋯ and a done button that closes the keyboard. While the keyboard is down, the bottom SHALL show *Checklist*, *Attach* and a compose button that opens a new note. The ⋯ menu SHALL open under its button with its right edge in line with the button's, fully inside the screen with a margin, and with round corners. Every button SHALL have a name a screen reader says.

#### Scenario: Done closes the keyboard
- **WHEN** the person is editing and taps the done button
- **THEN** the keyboard closes, the change is kept, and the bottom bar with the compose button shows

#### Scenario: The ⋯ menu fits on a small phone
- **WHEN** the person taps ⋯ on a note's page on a 375-point-wide phone
- **THEN** the menu shows *Copy* under the ⋯ button, its right edge in line with the button and inside the screen, with no part cut off

## ADDED Requirements

### Requirement: Links in a note open in the browser

A web address in a note's words SHALL show as a link in the accent color, also when it was typed or pasted as plain text. While the person reads the note, a tap on the link SHALL open it in the phone's browser; while they edit, a tap SHALL put the cursor in it. Showing a link SHALL NOT change the note's stored words or send it again.

#### Scenario: Open a pasted address

- **WHEN** a note holds `https://id.onfido.com/XX6L46TU` as plain text and the person taps it with the keyboard down
- **THEN** the phone's browser opens that address, and the note is not marked to send again

#### Scenario: Edit a link's words

- **WHEN** the person is editing and taps the address
- **THEN** the cursor goes into the address and no browser opens

### Requirement: Tap Waiting to send to send now

While a note waits to send, its *Waiting to send* line on the note's page SHALL be a button that sends what waits now, and SHALL say *Sending…* while it goes.

#### Scenario: Send a waiting note

- **WHEN** a note says *Waiting to send*, the phone has a connection, and the person taps it
- **THEN** the phone sends what waits, the line says *Sending…*, then *Sent*
