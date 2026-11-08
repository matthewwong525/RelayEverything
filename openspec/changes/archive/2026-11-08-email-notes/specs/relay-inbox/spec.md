## ADDED Requirements

### Requirement: Each person gets an email address for notes

Each person SHALL have their own random address for notes on the server's mail domain, shown on their page, which they can replace with a new one. Any mail to it SHALL become one note in that person's space, whoever sends it, with the subject and plain words as its text, *Email* as where it came from, and the time it was sent. Attached files SHALL become the note's files, within the limits of note files, sealed like any other note file; a file left out SHALL be named in the note. The same mail delivered twice SHALL be stored once. The note SHALL reach the person's webhooks and AI like a note from the app. No mail SHALL be sent back.

#### Scenario: Forward a receipt
- **WHEN** a shop's mail with a PDF reaches the person's secret address through a mail rule
- **THEN** a note holds the subject, the words and the PDF, with *Email* as where it came from

#### Scenario: A new address
- **WHEN** the person replaces their address
- **THEN** mail to the old address becomes no note in their space

### Requirement: The shared address takes mail only from a checked sign-in email

The server SHALL take mail at one shared address on its mail domain. Mail there that passes the mail domain's sender checks SHALL become a note for the person whose sign-in email sent it. Mail that fails the checks SHALL make no note and SHALL NOT be kept. Mail to any other address on the domain SHALL be dropped.

#### Scenario: From the sign-in email
- **WHEN** the person writes to the shared address from their sign-in email, and the mail passes the sender checks
- **THEN** their page shows the note

#### Scenario: A forged sender
- **WHEN** mail reaches the shared address with a sign-in email in `From` but fails the sender checks
- **THEN** no note is made and nothing is kept

### Requirement: Mail from an email with no account is kept until it signs up

Mail to the shared address from a checked email that has no account SHALL be kept, sealed so that the stored data alone can't be read, for 30 days. When that email signs up, the kept mail SHALL become notes in the new person's space with their first times. Kept mail SHALL be deleted after 30 days. The server SHALL keep at most 100 messages and 50 MB for each email with no account, and drop the oldest past that.

#### Scenario: Writes first, signs up later
- **WHEN** an email with no account writes *Idea: ring charger* to the shared address, and signs up 3 days later
- **THEN** the new person's page shows the note with the time it was first sent

#### Scenario: Never signs up
- **WHEN** kept mail is older than 30 days
- **THEN** the server deletes it and its files

### Requirement: Email turns on only when its server set it up

Email in SHALL work only on a server whose owner set its mail domain. Without it, the page SHALL show no Email card, and a self-hosted server SHALL work as before.

#### Scenario: No mail domain
- **WHEN** a self-hosted server has no mail domain set
- **THEN** the page shows no Email card, and every other part works

### Requirement: The card warns that email is not sealed

The *Email* card SHALL say that email is not sealed on the way, and that health and location details should not be sent that way.

#### Scenario: The card
- **WHEN** the person opens the *Email* card
- **THEN** it shows the warning under the address
