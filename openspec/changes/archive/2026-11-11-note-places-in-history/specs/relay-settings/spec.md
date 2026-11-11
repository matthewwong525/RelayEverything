## MODIFIED Requirements

### Requirement: Settings shows the same rows on the phone and the web

Settings SHALL show, in this order, the account card and *Appearance*, on the phone and in the browser, with the same names. The phone SHALL also show *Voice notes* (the speech model) after *Appearance*, and the app's version and build at the bottom; the browser SHALL NOT show them. Settings SHALL have no *Notes* group and no switch that pins a place to notes. Settings SHALL have no *Advanced* row, and SHALL NOT hold health, places, the calendar, photos, AI apps, email notes or webhooks. A signed-out phone SHALL make no network request when it opens Settings.

#### Scenario: The phone, signed in
- **WHEN** a person signed in as you@example.com opens Settings on the phone
- **THEN** it shows the account card with you@example.com, *Appearance*, *Voice notes* and the version, in that order, and no *Pin notes to where I am*

#### Scenario: The browser
- **WHEN** the same person opens Settings in the browser
- **THEN** its list shows *Account* and *Appearance*, in that order, and nothing else
