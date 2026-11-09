## MODIFIED Requirements

### Requirement: Earlier notes go only when the person says so

When the person turns sending on and notes exist that never went to the server, the app SHALL ask whether to send them, and SHALL send them only on a yes. When a phone that sent to the person's own webhook signs in to Relay Everything, the notes written on this phone that went only to the webhook SHALL count as earlier notes too. A note already on the person's Relay Everything space SHALL NOT be asked about or sent again.

#### Scenario: Only new notes
- **WHEN** the person turns sending on with 42 unsent notes and picks only new notes
- **THEN** none of the 42 is sent, and notes written after that are sent

#### Scenario: Turned on again later
- **WHEN** the person turns sending on again after a time with it off
- **THEN** the app asks again about every note that never went to the server and was not already waiting to send

#### Scenario: From the webhook to Relay Everything
- **WHEN** a phone sent 12 notes to the person's own webhook, then signs in to Relay Everything, and the person picks *Send them*
- **THEN** the 12 notes go to Relay Everything, oldest first, and the webhook gets none of them again from the phone
