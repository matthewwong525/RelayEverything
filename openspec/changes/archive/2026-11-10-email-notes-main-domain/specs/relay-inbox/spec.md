## ADDED Requirements

### Requirement: The shared server takes note mail on its main domain

The shared Relay Everything server SHALL take note mail at `relayeverything.com` itself: the shared address SHALL be `notes@relayeverything.com`, and each person's address SHALL be `notes-<code>@relayeverything.com`. A person's code SHALL stay the same when the domain changes. Mail to an address on `in.relayeverything.com` SHALL make no note. Mail to an address on `relayeverything.com` that has its own mail rule SHALL keep going where that rule sends it.

#### Scenario: Write to the short address
- **WHEN** the person writes to `notes@relayeverything.com` from their sign-in email, and the mail passes the sender checks
- **THEN** their page shows the note, and their *Email notes* page shows their address ending with `@relayeverything.com`

#### Scenario: The old address
- **WHEN** mail reaches `notes@in.relayeverything.com` or a person's old `notes-<code>@in.relayeverything.com`
- **THEN** no note is made
