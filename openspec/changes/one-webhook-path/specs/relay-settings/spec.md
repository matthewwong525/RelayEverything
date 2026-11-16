## REMOVED Requirements

### Requirement: The account card says where notes go, in few words

**Reason**: Its scenario *Private data to the webhook* names a choice that this change removes.
**Migration**: Replaced by *The account card says where data goes, in few words*, the same rule with that scenario gone.

### Requirement: Advanced on the Account page holds the developer options

**Reason**: It held *Only to my own webhook*, which this change removes.
**Migration**: Replaced by *Advanced holds the webhooks and API keys*, the same pages without the switch.

## ADDED Requirements

### Requirement: The account card says where data goes, in few words

Signed in, the account card SHALL show the account's email and *Signed in*, and nothing more. Sending to the person's own webhook with no account, it SHALL say *My own webhook* and show the webhook's address. Signed out, it SHALL say *Sign in to Relay Everything* and that notes stay on the phone until the person signs in. A tap SHALL open the sign-in when signed out, else the Account page.

#### Scenario: Signed in
- **WHEN** a signed-in person opens Settings
- **THEN** the account card shows their email and *Signed in*, and no other line

#### Scenario: Signed out
- **WHEN** a person opens Settings on a new install
- **THEN** the account card says *Sign in to Relay Everything*, and no request leaves the phone

### Requirement: Advanced holds the webhooks and API keys

*Advanced* on the Account page SHALL hold *Webhooks*, and in the browser *API keys*, each a row that opens its page and says in one line what it is for. On the phone, *Webhooks* SHALL say a person does not need it to use Relay Everything, list the webhooks by name, and open the person's Relay Everything page to add or change one; it SHALL hold no choice of where data goes. In the browser, *Webhooks* SHALL add, change and remove webhooks as before. *API keys* SHALL list the person's API keys, each with *Turn off*, and *Add an API key*, which shows the new key once. No page but *API keys* SHALL show a key.

#### Scenario: The phone's Webhooks page
- **WHEN** a signed-in person opens *Webhooks* on the phone
- **THEN** it lists their webhooks by name and a link to add or change one on their page, and shows no switch

#### Scenario: The default
- **WHEN** a person signs in, never opens *Webhooks*, and turns on Health
- **THEN** their health readings go to Relay Everything
