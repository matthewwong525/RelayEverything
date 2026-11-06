## REMOVED Requirements

### Requirement: Only the owner can connect
**Reason**: Anyone with an account can now connect their own AI app to their own space.
**Migration**: Replaced by *Each person connects only their own space*.

## ADDED Requirements

### Requirement: Each person connects only their own space

The connector SHALL admit a sign-in by any person with an account on its server, and each connection SHALL read only that person's space. It SHALL refuse every request that has no valid connector token, including one carrying a device key or a site session.

#### Scenario: Two people connect
- **WHEN** Ana and Ben each connect Claude and ask for today's notes
- **THEN** each gets only their own notes

#### Scenario: Someone with no account signs in
- **WHEN** a person with no account completes the connector sign-in on a server with sign-up off
- **THEN** no connection is made and no data is returned

#### Scenario: A request with no token
- **WHEN** a request reaches the connector without a valid token
- **THEN** it is refused before any data is read
