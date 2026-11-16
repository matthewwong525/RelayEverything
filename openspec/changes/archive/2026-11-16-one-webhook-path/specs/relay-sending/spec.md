## REMOVED Requirements

### Requirement: Signing in sends to one place the person picks

**Reason**: It allowed a second place for private data, *Only to my own webhook*, which this change removes.
**Migration**: Replaced by *Signing in sends everything to one place*, which keeps the one-step start and drops the second place.

## ADDED Requirements

### Requirement: Signing in sends everything to one place

Sending SHALL start in one step: when the person signs in to Relay Everything or saves their own webhook, the phone SHALL send there, after the question about earlier notes. The app SHALL have no separate switch for sending. Notes, health, location points, calendar events and photos SHALL all go to that one place: Relay Everything while signed in, or the person's own webhook with no account, never both. The offline default, the earlier-notes question, and health and location only while sending SHALL work the same for both places.

#### Scenario: Signing in starts sending
- **WHEN** the person taps *Sign in to Relay Everything* in Settings, signs in, and picks *Only new notes*
- **THEN** the phone sends new notes to their server, and Settings shows their email

#### Scenario: Signing in from the phone's own webhook
- **WHEN** a phone that sends everything to its own webhook signs in to Relay Everything
- **THEN** notes, health, places, calendar and photos all go to Relay Everything from then on, and the phone sends nothing more to its webhook
