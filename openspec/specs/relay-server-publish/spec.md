# relay-server-publish Specification

## Purpose
Keep every Relay Everything server Worker on the published version, and make sure each environment's webhook catch-up reaches a Worker that can open the spaces.

## Requirements

### Requirement: Catch-up wake-ups reach a Worker with spaces

In each environment, the queue that the spaces Worker sends its catch-up wake-ups to SHALL be consumed by a Worker in the same environment that binds `SPACES`. The repository's checks SHALL fail when a configuration breaks this pairing.

#### Scenario: Staging wake-up is consumed by the staging shared server

- **WHEN** a staging space's alarm sends a wake-up for a webhook that fell behind
- **THEN** the message goes to `relay-everything-server-webhooks-staging`, which the staging shared server consumes, and the missed items are sent

#### Scenario: A config points the wake-up at a queue no spaces Worker reads

- **WHEN** a change sets a spaces Worker environment's producer queue to one consumed only by a Worker without `SPACES`, or by none
- **THEN** the config test fails and names the environment and the queue

### Requirement: The server is updated after each publish

After each publish, one command SHALL update, from the published commit, the staging spaces Worker, the staging AI connector and the staging shared server in that order, then the live shared server. It SHALL print one `result=` line: `deployed` with the commit and each Worker, `failed` with the step that failed, or `dry-run`. A failure at any staging step SHALL leave the live shared server unchanged.

#### Scenario: Publish updates staging then live

- **WHEN** the command runs after a publish of commit X
- **THEN** the staging spaces Worker, staging AI connector, staging shared server and live shared server each run commit X, and the command prints `result=deployed` with X

#### Scenario: A staging step fails

- **WHEN** the staging shared server's build or deploy fails
- **THEN** the command prints `result=failed` naming that step, and the live shared server still runs its earlier version

#### Scenario: Dry run

- **WHEN** the command runs with `--dry-run`
- **THEN** it builds each part and deploys nothing, and prints `result=dry-run`
