# relay-app-device-check Specification

## Purpose
Check the Relay Everything phone app on an iPhone simulator in the cloud, on request, so a change can be seen on an iPhone screen before it is published, from a Linux computer.

## Requirements

### Requirement: The check runs only on request, and only for the owner's branches

The device check SHALL start only when it is started by hand (from `/verify` or GitHub) or when the *check on iPhone* label is put on a pull request whose branch is in RelayEverything itself. A push SHALL NOT start it. A pull request from a fork SHALL never run it with a secret.

#### Scenario: A labelled pull request from the owner's branch
- **WHEN** the owner puts the *check on iPhone* label on a pull request from a RelayEverything branch
- **THEN** the check runs on that branch's newest commit

#### Scenario: A labelled pull request from a fork
- **WHEN** the label is put on a pull request from a fork
- **THEN** the check does not run, and no secret reaches that code

### Requirement: The fixed tour runs on every check

Each check SHALL build the app for the simulator with no signing key, open it on an iPhone simulator, and go through a fixed tour of the main screens (timeline, new note, save, settings), with a screenshot of each screen and a video of the run. The tour SHALL use no AI.

#### Scenario: The app builds and opens
- **WHEN** a check runs on a commit whose app builds
- **THEN** the results hold one screenshot per tour screen and a video, and the report says which tour steps passed

#### Scenario: The app does not build or does not open
- **WHEN** the simulator build fails or the app does not open
- **THEN** the check ends as *broken*, with the error, and the Claude run does not start

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

### Requirement: The results come back to the person

Each check SHALL keep its report, screenshots and video with the run. When the check is for a pull request, the report SHALL also go on the pull request, with a link to the run. `/verify` on this computer SHALL start the check for a change to `mobile/`, wait for it, and show the report and pictures in the chat.

#### Scenario: `/verify` on a phone app change
- **WHEN** `/verify` checks a change that touches `mobile/`
- **THEN** it starts the device check on the saved commit, and the chat shows the verdict, the screenshots and the video's place

#### Scenario: The check takes too long
- **WHEN** the check does not finish in its time limit
- **THEN** `/verify` reports the device check as not verified, with what finished and the link to the run

### Requirement: A newer check replaces an older one on the same branch

A check started for a branch SHALL cancel a check of the same branch that has not finished, so only the newest commit is checked. A release's tour gate SHALL never be cancelled by another check.

#### Scenario: Two checks on one branch
- **WHEN** a check starts on a branch while an older check of that branch still runs
- **THEN** the older check stops as cancelled, and the newer one runs to the end

#### Scenario: A release runs its tour
- **WHEN** a release's tour gate runs and someone starts a check on a branch
- **THEN** the release's tour gate goes on to the end
