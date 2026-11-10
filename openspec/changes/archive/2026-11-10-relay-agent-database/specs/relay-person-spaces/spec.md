## MODIFIED Requirements

### Requirement: A person can delete their account

A signed-in person SHALL be able to delete their account after they confirm it. Deleting SHALL remove their space with its memory table, their agents' database, their recordings, their knowledge web, their device keys, their sessions and their AI app grants, and SHALL leave every other person's data untouched.

#### Scenario: Ana deletes her account
- **WHEN** Ana confirms *Delete my account*
- **THEN** her phone's next send is refused, her AI app is refused, signing in again makes a new empty space, and Ben's data is unchanged

#### Scenario: Ana's knowledge web goes with her account
- **WHEN** Ana confirms *Delete my account*
- **THEN** her knowledge web is deleted, and a pass she had stops working

#### Scenario: Ana's agents' database goes with her account
- **WHEN** Ana confirms *Delete my account*
- **THEN** her agents' database is deleted, and signing in again gives an empty one
