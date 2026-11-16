## REMOVED Requirements

### Requirement: Nights and workouts go where health goes

**Reason**: It named a second place for health while signed in, *Only my own webhook*, which this change removes.
**Migration**: Replaced by *Nights and workouts go where the phone sends*.

## ADDED Requirements

### Requirement: Nights and workouts go where the phone sends

Nights and workout details SHALL go where the phone's health goes: while signed in, to the person's Relay Everything space and from there only to webhooks ticked for *Health*; with no account, straight to the person's own webhook. A resend that changes nothing SHALL wake no webhook.

#### Scenario: A webhook not ticked for Health
- **WHEN** a night arrives and the person has one webhook ticked for *Health* and one not
- **THEN** only the ticked webhook gets the night

#### Scenario: No account, own webhook
- **WHEN** a phone with no account sends to its own webhook
- **THEN** the night and the full workout go straight to that webhook, and no server gets them
