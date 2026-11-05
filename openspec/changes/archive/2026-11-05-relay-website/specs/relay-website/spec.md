# Spec Delta

## Purpose

Give Relay one public website: what Relay is, and docs for its app, set-up, server API, connections and ring, kept current and free of anything private.

## ADDED Requirements

### Requirement: The website is public and separate

The Relay website SHALL open for anyone at relayeverything.com and www.relayeverything.com with no login. It SHALL be served as static pages by a site that holds no binding to Relay's data, the memory store, or any key, and the private site SHALL keep its login unchanged.

#### Scenario: A stranger opens the website
- **WHEN** a person with no account opens the website's address
- **THEN** the home page loads, and every docs page opens from its menu

#### Scenario: The private site stays private
- **WHEN** the website is live
- **THEN** the private site's pages and Relay's API still ask for the login or a device key

### Requirement: The home page introduces Relay

The home page SHALL present Relay as a way to get a person's own data (notes, health, location) off their phone and devices into a place they choose, where their own AI can read it. It SHALL show the ring as one way to take notes, not as the headline, and it SHALL link to the Android app, the iPhone TestFlight invite, the app's public code, and the docs.

#### Scenario: A reader wants the app
- **WHEN** a reader opens the home page
- **THEN** they find a link to the Android app, one to TestFlight, and one to the docs

#### Scenario: A reader learns what Relay is
- **WHEN** a reader opens the home page
- **THEN** the headline speaks of their own data in a place they choose, and the ring appears lower as one way to take notes

### Requirement: The docs cover all of Relay

The docs SHALL hold a menu and a search box, with pages for getting started (what you need, install the app, connect a phone, the Pebble webhook), using the app (notes, health, location, settings), the ring (how it works, parts and battery, the board, 3D models and test prints), the server API, connections, and privacy. A connection that is not built yet SHALL be shown as coming, with no steps that don't work.

#### Scenario: A reader sets up the Pebble webhook
- **WHEN** a reader opens the Pebble webhook page
- **THEN** it gives the route, the headers to add, the signing setting, and what a test sends back

#### Scenario: A connection is not built yet
- **WHEN** sending to your own database, the AI assistant connection, or the example skill and tables has not been published
- **THEN** its entry says it is coming, and no page gives set-up steps for it

### Requirement: The API reference matches the server

The API pages SHALL be made from the Relay server's own route descriptions: each route's method, path, input fields, output fields, errors and an example. A route change that leaves its page different from what the routes make SHALL fail the project's checks.

#### Scenario: A route gains a field
- **WHEN** a change adds a field to a Relay route but not to the API page
- **THEN** the checks fail and say to make the API page again

### Requirement: Nothing private is published

Before any update, every built file SHALL be checked, and the update SHALL be refused, with nothing deployed, when a file holds text shaped like a key, a value from the project's private settings, an email address, or the private site's address. The refusal SHALL name the file and why, never the value. The docs SHALL hold no personal notes, health or location data.

#### Scenario: A page holds the private site's address
- **WHEN** a docs page names the private site's address
- **THEN** the update stops, names that page, and the live website stays as it was

#### Scenario: A clean update
- **WHEN** no built file holds a key, a private value, an email address or the private address
- **THEN** the website is updated

### Requirement: The website updates after each publish and previews before

After each publish, the website SHALL be rebuilt from the published project and updated, and the step SHALL report one result: deployed with its address, refused with the file named, or failed. A plan's build SHALL be viewable at a separate preview address before it is published, leaving the live website unchanged.

#### Scenario: A publish changes a docs page
- **WHEN** a change that edits a docs page is published and the update step runs
- **THEN** the live website shows the new page, and the step reports the address

#### Scenario: A preview
- **WHEN** a plan that changes the website is built
- **THEN** its pages open at the preview address, and the live website is unchanged
