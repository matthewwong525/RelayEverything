## MODIFIED Requirements

### Requirement: Signing in sends to one place the person picks

Sending SHALL start in one step: when the person signs in to their Relay Everything server, connects with a key, or saves their own webhook, the phone SHALL send there, after the question about earlier notes. The app SHALL have no separate switch for sending. Notes SHALL go to that one place only, never both. Signed in to Relay Everything, health, location points, calendar events and photos SHALL go either to Relay Everything or, when the person picks *Only my own webhook*, only to their own webhook, never to both. The offline default, the earlier-notes question, and health and location only while sending SHALL work the same for both places.

#### Scenario: Signing in starts sending

- **WHEN** the person taps *Sign in to Relay Everything* in Settings, signs in, and picks *Only new notes*
- **THEN** the phone sends new notes to their server, and Settings shows their email

#### Scenario: Earlier notes with a webhook

- **WHEN** the person picks *Send to my own webhook instead* with 12 notes that never left the phone
- **THEN** the app asks whether to send the 12, sends them to the webhook only on a yes, and Settings says *My own webhook*

#### Scenario: Switching private data back to Relay Everything

- **WHEN** a signed-in person with *Only my own webhook* on and 40 health samples waiting picks *Relay Everything*
- **THEN** the 40 samples and all later private data go to Relay Everything, and nothing more goes to the webhook from the phone
