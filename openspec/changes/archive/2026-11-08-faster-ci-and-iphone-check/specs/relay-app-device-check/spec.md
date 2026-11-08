## MODIFIED Requirements

### Requirement: Claude checks the change on the simulator, with narrow powers

When an Anthropic key or a Claude Code token is set, the check SHALL run Claude on the same machine after the tour. Claude SHALL get what the change should do, use only the simulator, its results folder and harmless file commands, and write a report that gives what it tried, what it saw, and one verdict: *works*, *broken* or *could not check*, each with a reason. Claude SHALL keep its report up to date as it goes, so a stop keeps what it found. Claude SHALL NOT push, change the repository, or read other secrets. With no key set, the check SHALL run the tour only and say that Claude was skipped. When Claude runs but gives no verdict, the check SHALL fail and say why, such as out of time, out of turns or commands refused. The run SHALL keep a log of each command Claude ran and each one that was refused, with no key in it.

#### Scenario: A key is set
- **WHEN** a check runs with the key set and the tour passed
- **THEN** the report holds Claude's steps, its screenshots and one verdict with a reason, and the run's files hold Claude's step log

#### Scenario: No key is set
- **WHEN** a check runs with no Anthropic key or Claude Code token
- **THEN** the tour still runs, and the report says *Claude skipped: no key*

#### Scenario: Claude stops with no verdict
- **WHEN** Claude runs out of time or turns, or stops after refused commands, before it writes a verdict
- **THEN** the check fails, the report says why and keeps the scenarios Claude already wrote, and the step log shows the last commands

## ADDED Requirements

### Requirement: A newer check replaces an older one on the same branch

A check started for a branch SHALL cancel a check of the same branch that has not finished, so only the newest commit is checked. A release's tour gate SHALL never be cancelled by another check.

#### Scenario: Two checks on one branch
- **WHEN** a check starts on a branch while an older check of that branch still runs
- **THEN** the older check stops as cancelled, and the newer one runs to the end

#### Scenario: A release runs its tour
- **WHEN** a release's tour gate runs and someone starts a check on a branch
- **THEN** the release's tour gate goes on to the end
