# relay-person-spaces Specification

## Purpose
Keep each person's Relay Everything data in their own locked space on a shared server, so no person, key or AI grant can reach another person's data.

## Requirements

### Requirement: Each person's data is in their own space

Each person with an account SHALL have their own space that holds their notes, health samples, places, chats, devices and webhooks, and no one else's. Their recordings SHALL be kept apart from every other person's, and each stored file SHALL be locked with a key held only in their space, so the file store alone never gives a playable recording. The shared list of accounts SHALL hold only who has an account, how they sign in and which key belongs to whom: no note, sample, place, chat or recording.

#### Scenario: Two people send notes
- **WHEN** Ana's phone and Ben's phone each send a note
- **THEN** Ana's page shows only Ana's note, and Ben's page shows only Ben's

#### Scenario: A recording is opened from the file store directly
- **WHEN** someone downloads a recording's file straight from the file store
- **THEN** it can't be played without its person's space

#### Scenario: The shared list is read
- **WHEN** someone reads the shared list of accounts
- **THEN** it holds emails and key fingerprints, and no note, health, place, chat or recording

### Requirement: No way into another person's space

The server SHALL open a space only for the person it belongs to: their signed-in session, one of their device keys, or one of their AI app grants. No route, page, tool or script SHALL open a space by a person or space named in a request, and the server's owner SHALL have no way to read another person's space through the product. The repository's checks SHALL fail when code opens a space from anything but the caller's own identity.

#### Scenario: The owner looks for another person's notes
- **WHEN** the server's owner, signed in, asks any route for Ben's notes by any id or address
- **THEN** they get only their own data or a refusal, never Ben's

#### Scenario: A change adds a way in
- **WHEN** a change adds a route that opens a space from a person id in the request
- **THEN** the checks fail before the change can ship

### Requirement: A person can delete their account

A signed-in person SHALL be able to delete their account after they confirm it. Deleting SHALL remove their space, their recordings, their device keys, their sessions and their AI app grants, and SHALL leave every other person's data untouched.

#### Scenario: Ana deletes her account
- **WHEN** Ana confirms *Delete my account*
- **THEN** her phone's next send is refused, her AI app is refused, signing in again makes a new empty space, and Ben's data is unchanged
