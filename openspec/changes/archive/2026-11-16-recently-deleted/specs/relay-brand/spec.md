## ADDED Requirements

### Requirement: The app shows no toast; a problem shows as an alert

The phone app, the web page and the Mac app SHALL show no bar of words at the bottom of the screen, as Apple Notes does. A problem the person must know of, such as a browser that did not open or a note that did not go, SHALL show as an alert in the middle of the screen with its words and *OK*. A done step that the screen already shows, such as a copy or a delete, SHALL show no message.

#### Scenario: Copy the email address
- **WHEN** the person taps copy on the *Email notes* page
- **THEN** the address is copied and no message shows

#### Scenario: The browser does not open
- **WHEN** the person taps a link and the browser does not open
- **THEN** an alert says *The browser did not open* and *Try again.*, with *OK*, and nothing covers *Search* or *New note*
