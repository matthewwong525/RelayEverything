## REMOVED Requirements

### Requirement: Only the owner manages webhooks, and only safe addresses
**Reason**: A server now has many people, each with their own webhooks; *the owner* no longer names who manages one.
**Migration**: Replaced by *Each person manages only their own webhooks, and only safe addresses*.

## ADDED Requirements

### Requirement: Each person manages only their own webhooks, and only safe addresses

Only the signed-in person whose space holds a webhook SHALL add, change, test, pause or remove it, or read its deliveries; a device key and every other person SHALL be refused. A webhook SHALL send only its own person's data. A webhook address SHALL be `https` and SHALL NOT point at `localhost`, a private or link-local network, or Relay Everything's own site. A webhook's secret SHALL be shown once, when it is made or replaced, and never again.

#### Scenario: A device key tries to add a webhook
- **WHEN** a phone's device key calls the add-webhook route
- **THEN** the server refuses it and adds nothing

#### Scenario: Another person's data
- **WHEN** Ben stores a note and Ana has a webhook
- **THEN** Ana's webhook gets nothing from Ben

#### Scenario: An address on a private network
- **WHEN** a person adds `https://192.168.1.10/hook` or `http://db.example.com`
- **THEN** the server refuses it and says why
