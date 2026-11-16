## REMOVED Requirements

### Requirement: Private data can go only to the webhook while notes sync

**Reason**: Two places at once lost notes: a person's webhook got health, places, calendar and photos from the phone, but no notes, because no webhook was added on their page.
**Migration**: A phone with the choice on moves to Relay Everything at the update and says so once, by the new requirement *A signed-in phone sends to no webhook itself*. To keep data off Relay Everything, use the app with no account and the phone's own webhook.

## ADDED Requirements

### Requirement: A signed-in phone sends to no webhook itself

Signed in to Relay Everything, the phone SHALL send notes, their files, health, location points, stays and trips, calendar events and photos only to Relay Everything, and SHALL send nothing to any webhook itself. Relay Everything SHALL send each kind on only to the webhooks the person ticked for it. The phone SHALL keep its own webhook's address and secret while signed in, and SHALL use them again only after the person signs out and picks their own webhook. A phone that had *Only to my own webhook* on before the update SHALL send its waiting and later health, places, calendar and photos to Relay Everything, and SHALL show one message, once, that says so and opens *Webhooks*.

#### Scenario: Signed in with a webhook kept
- **WHEN** a signed-in person whose phone keeps a webhook writes a note and has health and photos on
- **THEN** the note, the health samples and the photos reach Relay Everything, and the phone's receiver gets no message from the phone

#### Scenario: A phone that had the choice on
- **WHEN** a phone that sent health only to its own webhook updates, with 40 health samples waiting, and opens
- **THEN** the 40 samples and later ones go to Relay Everything, one message says that everything now goes through Relay Everything, and the message does not show again
