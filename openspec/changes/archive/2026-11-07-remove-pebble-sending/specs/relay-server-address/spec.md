## REMOVED Requirements

### Requirement: The old address forwards for 30 days

**Reason**: Its first scenario uses the Pebble webhook, which no longer sends. It is replaced by *The old address forwards for 30 days after the move*, with the same rule.

**Migration**: None.

## ADDED Requirements

### Requirement: The old address forwards for 30 days after the move

For 30 days after the move, the old relay-ring workers.dev address SHALL pass every request on to the new site with its method, body and key unchanged, and SHALL send a browser that opens a page to the same page at the new address. A request with no valid login or device key SHALL be refused, as at the new address. After the 30 days, the old address SHALL be removed only after the owner says yes.

#### Scenario: A phone sends to the old address
- **WHEN** a phone posts a note with its key to the old address in the 30 days
- **THEN** the new site keeps the note once, as if it was posted there

#### Scenario: A browser opens the old address
- **WHEN** the owner opens a page at the old address
- **THEN** the browser goes to the same page at app.relayeverything.com
