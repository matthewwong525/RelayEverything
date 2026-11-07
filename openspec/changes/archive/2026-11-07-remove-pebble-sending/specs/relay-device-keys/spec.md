## REMOVED Requirements

### Requirement: One key can be revoked alone

**Reason**: Its scenario names the Pebble app, which no longer sends. It is replaced by *One device key can be turned off alone*, with the same rule.

**Migration**: None.

## ADDED Requirements

### Requirement: One device key can be turned off alone

Turning off a device's key SHALL stop that device at its next request and leave other devices working. Making a key SHALL give only the key and its QR code text, and no signing secret.

#### Scenario: A lost phone
- **WHEN** Matthew turns off the Android phone's key
- **THEN** that phone's next sync is refused and the iPhone and Claude Code keep working

#### Scenario: A new phone key
- **WHEN** a person makes a phone key on the Relay Everything page
- **THEN** the page shows the key and its QR code once, and no signing secret
