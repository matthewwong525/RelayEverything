## MODIFIED Requirements

### Requirement: The company app and Relay Everything have their own addresses

The company app SHALL answer at admin.relayeverything.com behind the same login as before. Relay Everything's open server SHALL answer at app.relayeverything.com, where a person can sign up and the app opens at the top address with no company login. The company app SHALL NOT serve Relay Everything's page; its card SHALL link to app.relayeverything.com. A publish of either SHALL keep both addresses where they are.

#### Scenario: The company app stays private
- **WHEN** a person with no login opens admin.relayeverything.com
- **THEN** the site asks for the company login and shows no data

#### Scenario: A publish keeps the open address
- **WHEN** the company app is published
- **THEN** app.relayeverything.com still shows the Relay Everything sign-in

#### Scenario: A signed-in phone after the move
- **WHEN** a phone that sends to app.relayeverything.com with its key syncs after the move
- **THEN** its notes, health and places go through as before, with no new sign-in or key
