## ADDED Requirements

### Requirement: The proxy setting turns the routes on

The browser SHALL use the saved routes only while this computer's browser proxy setting is on. With the setting off, the browser SHALL go straight to sites from its next start and SHALL keep the saved route lines for when the setting is on again. A change to the setting SHALL never restart a running browser.

#### Scenario: Proxy on with saved lines
- **WHEN** the proxy setting is on and a first proxy line is saved
- **THEN** the next browser start goes through the routes in order

#### Scenario: Proxy turned off
- **WHEN** the person turns the browser proxy off
- **THEN** the next start goes straight to sites, and both saved route lines still hold their values

## MODIFIED Requirements

### Requirement: The status names the live route

`browse.mjs status` SHALL print `BROWSE_NETWORK=` with one of `upstream`, `upstream (backup)`, `direct (upstream unreachable)`, `direct (no upstream proxy)`, or `unknown (browser stopped)`.

#### Scenario: The Pi is off
- **WHEN** the first proxy failed and the upstream carries the traffic
- **THEN** status prints `BROWSE_NETWORK=upstream (backup)`
