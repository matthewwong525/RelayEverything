## ADDED Requirements

### Requirement: Sending goes to one place the person picks

When the person turns sending on, the app SHALL ask where to send: their Relay Everything server or their own webhook. It SHALL send to that one place only, never both. The offline default, the earlier-notes question, health and location only while sending, and turning sending off SHALL work the same for both places.

#### Scenario: Switching from the server to a webhook
- **WHEN** the person sends to the server, then picks their own webhook with items still waiting
- **THEN** the waiting items go to the webhook, and nothing more goes to the server

#### Scenario: Earlier notes with a webhook
- **WHEN** the person picks their own webhook with 12 notes that never left the phone
- **THEN** the app asks whether to send the 12, and sends them to the webhook only on a yes

#### Scenario: Settings names the place
- **WHEN** the person opens Settings with sending on
- **THEN** Settings shows where the phone sends, and in webhook mode says that nothing goes to Relay Everything
