## MODIFIED Requirements

### Requirement: The Account page shows the connection

Signed in to a Relay Everything server, the Account page SHALL show the account's email and server, *AI apps* and *Webhooks* with the names the server last gave, where health, places, calendar and photos go, *Open your Relay Everything page*, the server to change, and *Sign out*. A tap on *AI apps* or *Webhooks* SHALL open that part of the person's Relay Everything page. The private data choice SHALL offer *Relay Everything* and *Only my own webhook*, SHALL say that data already sent stays on the person's page, and, with *Only my own webhook* picked, SHALL show the webhook's address, *Send a test* and its last failure. Picking *Only my own webhook* with no webhook on the phone SHALL first open the webhook's setup, and SHALL change nothing if the person leaves it. *Sign out* SHALL ask first, then remove the phone's key and stop sending; notes from this phone SHALL stay on it. With sending to the person's own webhook, the page SHALL show its address, *Send a test*, *Sign in to Relay Everything* and *Stop sending*, and SHALL show no AI apps or webhooks list. Signing in from there SHALL keep the webhook for health, places, calendar and photos, as *Only my own webhook*, SHALL send notes to Relay Everything, and SHALL tell the person that their webhook gets notes only once they add it on their Relay Everything page. A closed or failed sign-in SHALL change nothing. The phone SHALL ask the server for the names and email only while it sends to a Relay Everything server.

#### Scenario: Signed in with connections

- **WHEN** the phone sends to a Relay Everything server and the person connected Claude and two webhooks
- **THEN** the Account page shows *AI apps* with *Claude*, *Webhooks* with both names and 2, and a tap on *Webhooks* opens the webhooks part of the person's page in the browser

#### Scenario: Signing out

- **WHEN** the person taps *Sign out* and confirms
- **THEN** the phone forgets its key, sending stops, the notes written on this phone stay, and Settings shows *Sign in to Relay Everything*

#### Scenario: Picking the webhook for private data

- **WHEN** a signed-in person with no webhook on the phone taps *Only my own webhook*, enters an address, and saves
- **THEN** the group shows *Only my own webhook* picked with the webhook's address and *Send a test*, and the *Health* folder says its readings go to the webhook

#### Scenario: Signing in from the webhook page

- **WHEN** the phone sends everything to the person's own webhook, and the person taps *Sign in to Relay Everything* on the Account page and signs in
- **THEN** the Account page shows the signed-in account with *Only my own webhook* picked, new notes go to Relay Everything, health readings still go only to the webhook, and a message says to add the webhook on the Relay Everything page to get notes there too

#### Scenario: Closing the sign-in

- **WHEN** the person taps *Sign in to Relay Everything* on the webhook Account page and closes the sign-in
- **THEN** the phone still sends everything to the webhook, and the Account page is unchanged
