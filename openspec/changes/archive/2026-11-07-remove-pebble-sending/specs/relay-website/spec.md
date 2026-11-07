## REMOVED Requirements

### Requirement: The docs cover all of Relay

**Reason**: It lists a Pebble webhook page and a scenario for it; the Pebble app no longer sends to a Relay Everything server. It is replaced by *The docs cover all of Relay Everything*.

**Migration**: None. The two Pebble pages go, and no page links to them.

## ADDED Requirements

### Requirement: The docs cover all of Relay Everything

The docs SHALL hold a menu and a search box, with pages for getting started (what you need, install the app, connect a phone), using the app (notes, health, location, settings), the ring (how it works, parts and battery, the board, 3D models and test prints), the server API, connections, and privacy. A connection that is not built yet SHALL be shown as coming, with no steps that don't work. No page SHALL tell a reader to send ring notes from the Pebble app to a Relay Everything server.

#### Scenario: A reader looks for the Pebble webhook
- **WHEN** a reader searches the docs for the Pebble webhook
- **THEN** no page gives steps to set it up, and the ring page says the Relay Everything ring will send through the phone app

#### Scenario: A connection is not built yet
- **WHEN** sending to your own database, the AI assistant connection, or the example skill and tables has not been published
- **THEN** its entry says it is coming, and no page gives set-up steps for it
