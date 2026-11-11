## ADDED Requirements

### Requirement: Each beta from main goes to the public beta

When a beta build from `main` goes to TestFlight, the run SHALL also add that build, once Apple has processed it, to the external TestFlight group *Public beta*, with the change's title as its *What to Test* text, and SHALL send it to Apple's beta review. A build that goes nowhere, such as one replaced by a newer commit, a branch build, a release check or a tag release, SHALL NOT go to the public beta. If Apple refuses the review only because another build still waits for beta review, the run SHALL say so and pass. The run SHALL NOT change the beta's description, its reviewer contact or the group's link.

#### Scenario: A change lands on main
- **WHEN** a change to the phone app lands on `main` and its build goes to TestFlight
- **THEN** that build joins the *Public beta* group with the change's title as *What to Test*, and it goes to beta review

#### Scenario: An earlier build still waits for review
- **WHEN** Apple refuses the new build's beta review because an earlier build is still waiting
- **THEN** the run notes it and passes, and the next change to the phone app sends again
