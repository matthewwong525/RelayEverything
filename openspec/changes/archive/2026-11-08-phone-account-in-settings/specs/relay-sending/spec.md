## REMOVED Requirements

### Requirement: Turning sending off keeps what exists

**Reason**: Sending has no separate switch now: signing out, or *Stop sending* for the person's own webhook, turns it off.
**Migration**: Replaced by *Signing out keeps what exists*.

### Requirement: Sending goes to one place the person picks

**Reason**: The person now picks the place when they sign in, and the place shows on the Account row in Settings.
**Migration**: Replaced by *Signing in sends to one place the person picks*.

## ADDED Requirements

### Requirement: Signing in sends to one place the person picks

Sending SHALL start in one step: when the person signs in to their Relay Everything server, connects with a key, or saves their own webhook, the phone SHALL send there, after the question about earlier notes. The app SHALL have no separate switch for sending. It SHALL send to that one place only, never both. The offline default, the earlier-notes question, and health and location only while sending SHALL work the same for both places.

#### Scenario: Signing in starts sending

- **WHEN** the person taps *Sign in to Relay Everything* in Settings, signs in, and picks *Only new notes*
- **THEN** the phone sends new notes to their server, and Settings shows their email

#### Scenario: Earlier notes with a webhook

- **WHEN** the person picks *Send to my own webhook instead* with 12 notes that never left the phone
- **THEN** the app asks whether to send the 12, sends them to the webhook only on a yes, and Settings says *My own webhook*

### Requirement: Signing out keeps what exists

*Sign out* and, for the person's own webhook, *Stop sending* SHALL stop all sending, keep every note written on the phone, and leave the server's copy untouched. *Stop sending* SHALL keep the webhook's address and secret on the phone, so the person can send there again without a new secret.

#### Scenario: Sign out and back in

- **WHEN** the person signs out and later signs in again
- **THEN** the server still holds the notes sent before, and the phone sends again with its new key
