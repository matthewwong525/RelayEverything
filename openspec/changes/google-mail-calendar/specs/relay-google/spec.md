## ADDED Requirements

### Requirement: A person connects their own Google account

A signed-in person SHALL be able to connect one Google account to their space from their Relay Everything page, allowing Gmail, Google Calendar, Google Drive and Google Contacts, and SHALL see which Google address is connected. Only that person's own sign-in SHALL connect or disconnect it.

#### Scenario: Ana connects Google
- **WHEN** Ana clicks *Connect Google* and allows all four at Google
- **THEN** her page shows her Google address as connected, and her callers can reach her Gmail, Calendar, Drive and Contacts

#### Scenario: Ana declines at Google
- **WHEN** Ana cancels on Google's page
- **THEN** nothing is connected and her page offers *Connect Google* again

### Requirement: Google data passes through and is never stored

Relay Everything SHALL fetch Gmail, Calendar, Drive and Contacts data from Google at the moment a caller asks and SHALL return it only to that caller. It SHALL NOT keep an email, an event, a file, a contact, or any part of one, in the space, the directory, the file store, a log or a webhook delivery. The only Google value it keeps SHALL be the person's Google sign-in, sealed with their space's own key.

#### Scenario: An AI reads an email
- **WHEN** Claude reads one of Ana's emails through the connector
- **THEN** the email goes to Claude, and afterwards Ana's space holds no part of it

#### Scenario: The sign-in in the database
- **WHEN** someone reads the space's storage without the space's key
- **THEN** they can't use Ana's Google sign-in

### Requirement: The API reaches Gmail, Calendar, Drive and Contacts

A caller that may use the Relay Everything API SHALL be able to send requests under `google/gmail/`, `google/calendar/` and `google/drive/` that reach the matching paths of Google's Gmail, Calendar and Drive APIs for the connected person, with the same methods and answers, and read-only requests under `google/contacts/` that reach Google's People API. Paths outside these four, a change to contacts, and a delete for ever of an email or a file SHALL be refused. A phone or chat key SHALL NOT reach Google.

#### Scenario: A script adds an event
- **WHEN** Ana's API key posts an event to `google/calendar/calendars/primary/events`
- **THEN** the event is on Ana's Google Calendar and the answer is Google's

#### Scenario: A path outside the four services
- **WHEN** a caller asks for Google Photos through the API
- **THEN** it is refused, and nothing is sent to Google

### Requirement: AI apps get Gmail, Calendar, Drive and Contacts tools

The AI connector SHALL offer tools to search and read email, send email, draft email, change an email's labels or move it to the bin, list, add, change and delete calendar events, search and read Drive files, save a new file, rename, move or bin a file, and find a contact, for the connected person only. A tool that sends, changes or deletes SHALL be marked as one that changes data. No tool SHALL delete an email or a file for ever.

#### Scenario: Asking about tomorrow
- **WHEN** Ana asks Claude what is on her calendar tomorrow
- **THEN** Claude lists her events from Google Calendar for that day

#### Scenario: Finding a file
- **WHEN** Ana asks Claude for the words of her lease in Drive
- **THEN** Claude finds the file and reads its text, and her space keeps none of it

#### Scenario: No Google connected
- **WHEN** Ben, who has not connected Google, asks Claude to search his email
- **THEN** the tool answers that he must connect Google on his Relay Everything page first

### Requirement: Each caller reaches only its own person's Google

A connected app, an API key or a session SHALL reach only the Google account connected to its own person's space. The person SHALL be told, before connecting an app, that it can read and send their email, change their calendar and Drive files, and read their contacts when Google is connected. An app connected before this capability SHALL reach Google only after it connects again.

#### Scenario: Two people
- **WHEN** Ben's API key asks for Gmail with Ana's id in the request
- **THEN** it reaches only Ben's Google account, or is refused when Ben has none

#### Scenario: An older connection
- **WHEN** an app Ana connected before this change asks for her email
- **THEN** it is refused with a message to connect again

### Requirement: Disconnect and account delete end Google access

*Disconnect* on the page and deleting the account SHALL each end the sign-in at Google and remove it from the space, so that the next Google request from any caller is refused.

#### Scenario: Ana disconnects
- **WHEN** Ana clicks *Disconnect* on the Google card and confirms
- **THEN** Google no longer accepts that sign-in, her space no longer holds it, and her apps' next Google request is refused
