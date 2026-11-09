# Spec Delta

## MODIFIED Requirements

### Requirement: The fixed tour runs on every check

Each check SHALL build the app for the simulator with no signing key, open it on an iPhone simulator, and go through a fixed tour of the main screens (timeline, new note, save, settings), with a screenshot of each screen and a video of the run. The tour SHALL use no AI. A tour step that fails SHALL run once more, alone, before it counts as failed; a step that passes on its second try SHALL count as passed, and the report SHALL say it needed a second try. A tour step that fails both tries SHALL end the check as *broken* before Claude starts. Each step's screenshot SHALL show the screen where that step passed or stopped.

#### Scenario: The app builds and opens
- **WHEN** a check runs on a commit whose app builds
- **THEN** the results hold one screenshot per tour screen and a video, and the report says which tour steps passed

#### Scenario: The app does not build or does not open
- **WHEN** the simulator build fails or the app does not open
- **THEN** the check ends as *broken*, with the error, and the Claude run does not start

#### Scenario: A step fails once on a slow simulator
- **WHEN** a tour step fails, then passes when it runs again
- **THEN** the step counts as passed, the report marks it *passed on the second try*, and the check goes on to Claude

#### Scenario: A step fails twice
- **WHEN** a tour step fails on both tries
- **THEN** the check ends as *broken*, names the step and shows its picture, and Claude does not start

## ADDED Requirements

### Requirement: A check can add tour steps for the change

A check SHALL accept the names of extra tour steps from the phone app's saved steps, and run them with the fixed tour, with the same retry, pictures and verdict. The extra steps SHALL run only on that check; a release's tour gate SHALL run the fixed tour alone.

#### Scenario: A check names the voice note step
- **WHEN** `/verify` starts a check that names the voice note step
- **THEN** the tour runs it after the fixed steps, and the report lists it with its result and picture

#### Scenario: A named step does not exist
- **WHEN** a check names a step that is not among the saved steps
- **THEN** the check ends as *could not check* before the build, and says which name is unknown

### Requirement: A crash is named in the report

When the app crashes during the tour or while Claude checks it, the report SHALL say first that the app crashed, with the crash's reason and its first lines, and the run SHALL keep the crash report. Claude SHALL be able to read crash reports while it works.

#### Scenario: The app crashes on a tap
- **WHEN** the app crashes during a check
- **THEN** the report's first lines say the app crashed and give its reason, and the crash report is in the run's files

### Requirement: The tour's result comes back before Claude's

When the tour ends, the check SHALL make the tour's result known before Claude finishes: `/verify` SHALL show it in the chat, and a check for a pull request SHALL post a short note there. The full report SHALL follow as before.

#### Scenario: The tour passes
- **WHEN** the tour of a check for a pull request passes and Claude starts
- **THEN** the pull request gets a note that the tour passed and Claude is checking, and `/verify` says the same, before the full report

### Requirement: A re-check tries only what did not work

When `/verify` checks a branch again after a fix, it SHALL give Claude only the scenarios that were not *works* in the last finished check of that branch, and the report SHALL list each skipped scenario as passed in that check, with its link. The tour SHALL still run in full. With no earlier finished check, every scenario SHALL be tried.

#### Scenario: A fix after one broken scenario
- **WHEN** the last check of the branch found 4 scenarios working and 1 broken, and `/verify` checks the fix
- **THEN** Claude tries only the broken scenario, and the report lists the other 4 as passed in the last check, with its link

#### Scenario: The first check of a branch
- **WHEN** `/verify` checks a branch with no finished check
- **THEN** Claude tries every scenario
