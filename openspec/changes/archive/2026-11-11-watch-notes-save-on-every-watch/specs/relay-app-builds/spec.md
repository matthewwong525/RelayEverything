# Spec Delta

## ADDED Requirements

### Requirement: The build check compiles the watch app for older watches

Each run of the watch app's tests SHALL first compile the watch app and its tests for the 32-bit Apple Watch architecture, and SHALL fail when that compile fails. The check SHALL say that it compiles and does not run that code, because no Apple Watch simulator runs with 32-bit numbers.

#### Scenario: A number too large for an older watch
- **WHEN** a change writes a whole number above 2,147,483,647 into a plain integer in the watch app or its tests
- **THEN** the watch tests job fails at the 32-bit compile and names the line
