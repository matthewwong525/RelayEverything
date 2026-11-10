## REMOVED Requirements

### Requirement: The web page is the Flutter app

**Reason**: It had the company app serve its own copy of the page; the page now opens at the server's top address, and the company app no longer serves it.

**Migration**: See "The web page is the Flutter app, at the server's top address" below.

## ADDED Requirements

### Requirement: The web page is the Flutter app, at the server's top address

Relay Everything's web page SHALL be the same Flutter app as the phone app, built for the browser. On the shared server and on a self-hosted server it SHALL open at the server's top address, `/`, with no login but the server's own sign-in. A sign-in with Apple or Google, a phone's connect and an AI app's connect SHALL come back to the app at that address. The company app SHALL NOT serve the page; its *Relay Everything* card SHALL link to the shared server. No part of the earlier page SHALL stay as a separate page.

#### Scenario: The top address opens the app
- **WHEN** a person with no sign-in opens `https://app.relayeverything.com/`
- **THEN** the app's own sign-in shows at that address, with no company login and no move to another path

#### Scenario: A sign-in comes back to the top address
- **WHEN** a person signs in with Google from `https://app.relayeverything.com/`
- **THEN** the browser comes back to `https://app.relayeverything.com/` signed in, with their notes
