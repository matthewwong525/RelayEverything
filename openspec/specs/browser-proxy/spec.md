# browser-proxy Specification

## Purpose
The shared browser sends its traffic through saved proxy routes, so sites see a home address and not this server's data-centre address, and no route detail enters the public repository.

## Requirements

### Requirement: Routes in order

Each browser connection to a site SHALL try the first proxy, then the upstream proxy, then this computer's own network, and move to the next route only when the one before fails. Local addresses SHALL always go direct.

#### Scenario: The first proxy works
- **WHEN** a first proxy line and an upstream line are saved and the first proxy opens the connection
- **THEN** the site sees the first proxy's address

#### Scenario: The first proxy is down
- **WHEN** the first proxy fails to open a secure connection and the upstream opens it
- **THEN** the page loads through the upstream, and for 60 seconds each new connection starts at the upstream

#### Scenario: Every route fails
- **WHEN** the first proxy and the upstream both fail to open a secure connection
- **THEN** the connection goes through this computer's own network, and the next connection tries the first proxy again

#### Scenario: A plain request fails at the first proxy
- **WHEN** the first proxy fails a plain (not secure) request
- **THEN** each new connection starts at the upstream for 60 seconds, even when the upstream fails too

#### Scenario: A plain request is never sent twice
- **WHEN** a route has taken a plain (not secure) request and then fails
- **THEN** the browser gets an error page, and no other route sends that request

### Requirement: Where the route lines come from

A browser start SHALL read `BROWSE_FIRST_PROXY` and `BROWSE_UPSTREAM_PROXY` from the environment or the primary worktree's `.env`, else from this computer's saved files `~/.wong-stack/camoufox/first-proxy` and `~/.wong-stack/camoufox/upstream-proxy`. A start that reads a key SHALL copy it to its file, readable only by its owner. Only the forwarder SHALL hold the lines; the browser SHALL get only a local forwarder address.

#### Scenario: No key in this repo
- **WHEN** this repo's `.env` has no proxy keys and the computer files hold lines
- **THEN** the start uses the lines from the computer files

#### Scenario: Nothing saved
- **WHEN** no key and no file holds a line
- **THEN** the browser goes direct and the status says `direct (no upstream proxy)`

### Requirement: Language and time zone follow the address

At start, the browser's time zone SHALL follow the address that sites see, and its language SHALL be English for that address's country.

#### Scenario: A Canadian address
- **WHEN** the route's address is in Canada
- **THEN** the browser starts with the `en-CA` language and a Canadian time zone

### Requirement: The status names the live route

`browse.mjs status` SHALL print `BROWSE_NETWORK=` with one of `upstream`, `upstream (backup)`, `direct (upstream unreachable)`, `direct (no upstream proxy)`, or `unknown (browser stopped)`.

#### Scenario: The Pi is off
- **WHEN** the first proxy failed and the upstream carries the traffic
- **THEN** status prints `BROWSE_NETWORK=upstream (backup)`

### Requirement: The proxy setting turns the routes on

The browser SHALL use the saved routes only while this computer's browser proxy setting is on. With the setting off, the browser SHALL go straight to sites from its next start and SHALL keep the saved route lines for when the setting is on again. A change to the setting SHALL never restart a running browser.

#### Scenario: Proxy on with saved lines
- **WHEN** the proxy setting is on and a first proxy line is saved
- **THEN** the next browser start goes through the routes in order

#### Scenario: Proxy turned off
- **WHEN** the person turns the browser proxy off
- **THEN** the next start goes straight to sites, and both saved route lines still hold their values

### Requirement: No route detail in the repository

No committed file SHALL hold a proxy address, login, password, or home address. `.env.example` SHALL hold only the blank key names.

#### Scenario: The public check runs
- **WHEN** `node scripts/public-check.mjs` runs on the change
- **THEN** it passes, and a search of the diff finds no proxy host, login, or home address
