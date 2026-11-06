# relay-sign-in Specification

## Purpose
Let people sign up and sign in to a Relay Everything server with an email code, Apple or Google, and let a self-hosted server admit only its owner unless they open it.

## Requirements

### Requirement: Anyone can sign up on the shared server

On the shared server, any person SHALL be able to make an account and sign in with a one-time code sent to their email, with Apple, or with Google. The first sign-in with an email SHALL make that person's account and an empty space; a later sign-in with the same email, by any of the three ways, SHALL reach the same space. A sign-in SHALL cost nothing per person.

#### Scenario: A new person signs up
- **WHEN** a person with no account enters their email and the code it receives
- **THEN** they are signed in to a new, empty space

#### Scenario: The same person uses Google later
- **WHEN** that person later signs in with Google using the same email
- **THEN** they reach the same space

### Requirement: Sign-in codes and sessions resist guessing and theft

A sign-in code SHALL work once, for a short time, and only for a few wrong tries. Asking for codes SHALL be limited per email and per network address. The server SHALL keep only a fingerprint of each code and session, never the code or session itself. Signing out SHALL end the session at once.

#### Scenario: Someone guesses codes
- **WHEN** a request sends wrong codes for an email past the limit
- **THEN** that code stops working, and the person must ask for a new one

#### Scenario: Signing out
- **WHEN** a person signs out
- **THEN** a later request with that session is refused

### Requirement: A self-hosted server lets in only its owner unless they open it

A self-hosted server SHALL let in only its owner's email by default, through its own Cloudflare login. Others SHALL be able to sign up only after the owner turns sign-up on, and each SHALL then get their own space.

#### Scenario: A stranger on a self-hosted server
- **WHEN** a person other than the owner tries to sign in to a self-hosted server with sign-up off
- **THEN** they are refused and no space is made
