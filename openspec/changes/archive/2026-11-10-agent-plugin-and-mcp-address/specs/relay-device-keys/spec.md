# Spec Delta

## ADDED Requirements

### Requirement: A computer's key saves chats and reads through the web API

A person SHALL get a computer's key only by confirming a sign-in link that the computer started, after seeing the computer's name and a short code that the computer also shows; the page's *Add a device* SHALL NOT make one. The key SHALL go to that computer only, through a request that works once and only for a few minutes and that only the computer that started it can finish, and SHALL never show. A computer's key SHALL add chats and their saves, and SHALL read the person's notes, health, sleep, workouts, places, calendar and saved chats and add notes through the web API, in that person's space only. It SHALL NOT reach a phone's routes, the page's own routes or the AI connector's tools, and SHALL NOT change or delete anything. An older chat key SHALL keep only adding chats. Turning a computer's key off SHALL stop it at its next request.

#### Scenario: A computer reads notes
- **WHEN** a computer's key asks the web API for today's notes
- **THEN** it gets its own person's notes for today, and no other person's

#### Scenario: Someone else's link
- **WHEN** a person confirms a link that another computer started, and that computer asks for its key after the few minutes, or without the secret it started with
- **THEN** no key is given

#### Scenario: An older chat key tries to read
- **WHEN** a chat key made before this change asks the web API for notes
- **THEN** it is refused, and its chat sends still work
