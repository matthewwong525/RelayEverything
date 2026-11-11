# Spec Delta

## MODIFIED Requirements

### Requirement: The phone sets up its webhook safely

The phone SHALL take only an `https://` address with no user name or password in it, and SHALL keep the secret only in the phone's secure key store. A private or home address SHALL be allowed. *Send a test* SHALL send a signed `webhook.test` message and show the receiver's answer. The setup SHALL be the same short form from the sign-in's *Don't want an account? Use your own webhook* and from *Webhooks* on the Account page: the address, a secret made on the phone to copy, *Send a test* and *Save*.

#### Scenario: An http address
- **WHEN** the person types an address that starts with `http://`
- **THEN** the phone refuses it and says the address must start with `https://`

#### Scenario: A test to a home receiver
- **WHEN** the person sets `https://192.168.1.20/relay` and taps *Send a test*
- **THEN** the phone sends the test and shows the answer's status
