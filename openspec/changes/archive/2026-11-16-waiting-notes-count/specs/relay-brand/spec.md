## MODIFIED Requirements

### Requirement: The sync state shows only when something is wrong

Under the title of Home and of the notes list, the phone app SHALL show a sync state only while sending is on and notes wait or can't go: the number of notes waiting, or *Key refused*, in words beside a small dot. Offline with no note waiting, it SHALL show no state; offline with notes waiting, it SHALL show the number waiting. The number SHALL count each note once that has anything waiting to send: the note itself, a change, a pin, a delete or a recover, and its photos, files and recordings. Health, places, calendar and photo data SHALL NOT count in it. The state SHALL be words, not a button. With every note sent, or with sending off, it SHALL show no state: Home SHALL show no line, and the notes list only its count. The dot SHALL pulse only while the waiting notes send, and SHALL stay still when the phone asks for reduced motion. There SHALL be no *Sync now* button: notes send by themselves, and a pull down on the page syncs now. The logo SHALL not move.

#### Scenario: Waiting notes send, then the state goes

- **WHEN** one note waits and the phone sends it
- **THEN** the state says *1 waiting* with a pulsing dot, and then Home shows no line and the notes list shows only its count

#### Scenario: Offline with every note sent shows no state

- **WHEN** sending is on, no note waits, and the phone can not reach the server
- **THEN** Home shows no line, the notes list shows only its count, and no *Offline* shows

#### Scenario: Reduced motion keeps the dot still

- **WHEN** the phone is set to reduce motion and a waiting note sends
- **THEN** the state says *1 waiting* and its dot does not move

#### Scenario: A note with its recordings counts once

- **WHEN** sending is on, the phone is offline, and 3 voice notes wait, each with its recording
- **THEN** the notes list says *3 notes · 3 waiting*, not *6 waiting*

#### Scenario: Health data does not count as a waiting note

- **WHEN** sending is on, no note waits, and health readings wait to send
- **THEN** Home shows no line, and the notes list shows only its count
