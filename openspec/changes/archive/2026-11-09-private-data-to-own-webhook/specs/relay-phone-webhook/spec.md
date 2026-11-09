## ADDED Requirements

### Requirement: Private data can go only to the webhook while notes sync

Signed in to Relay Everything, the person SHALL be able to choose that health samples, location points, calendar events and new photos go only to their own webhook, straight from the phone. With that choice on, the phone SHALL send none of them to Relay Everything, and SHALL still send notes, their files and a note's pinned place to Relay Everything. The choice SHALL be off by default. Notes and private data SHALL each keep their own order, and a failure on one side SHALL NOT hold back the other. When the webhook is missing or does not answer, private data SHALL wait on the phone and SHALL NOT go to Relay Everything instead. Data that reached Relay Everything before the choice SHALL stay there.

#### Scenario: Notes sync, health goes to the webhook

- **WHEN** a signed-in person picks *Only my own webhook* with health and location history on, then writes a note
- **THEN** the note reaches Relay Everything, the receiver gets `health.samples` and `location.points` messages, and no health sample or location point reaches Relay Everything

#### Scenario: The webhook is down

- **WHEN** the receiver answers 503 for a day while the choice is on
- **THEN** notes still reach Relay Everything, every waiting health sample, point, event and photo stays on the phone in order, and none of them goes to Relay Everything

#### Scenario: The webhook is gone after a restore

- **WHEN** the phone has the choice on but no longer holds the webhook's address and secret
- **THEN** private data waits on the phone, nothing private goes to Relay Everything, and the Account page asks the person to set the webhook again
