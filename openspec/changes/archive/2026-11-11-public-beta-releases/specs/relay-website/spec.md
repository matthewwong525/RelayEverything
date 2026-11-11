## MODIFIED Requirements

### Requirement: The home page introduces Relay

The home page SHALL present Relay as a way to get a person's own data (notes, health, location) off their phone and devices into a place they choose, where their own AI can read it. It SHALL name no ring, and it SHALL link to the Android app, the iPhone app's public TestFlight beta, the app's public code, and the docs.

#### Scenario: A reader wants the app
- **WHEN** a reader opens the home page
- **THEN** they find a link to the Android app, one to the public TestFlight beta, and one to the docs

#### Scenario: A reader learns what Relay is
- **WHEN** a reader opens the home page
- **THEN** the headline speaks of their own data in a place they choose, and no part of the page names a ring

## ADDED Requirements

### Requirement: The iPhone install steps open the public beta

Until the first App Store release, the install page SHALL tell a reader to install TestFlight and open the public TestFlight beta link, with no invite from a server's owner.

#### Scenario: A stranger installs the iPhone app
- **WHEN** a reader with no invite follows the install page's iPhone steps
- **THEN** they open the public link and can install the app through TestFlight
