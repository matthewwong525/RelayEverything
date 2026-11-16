# The iPhone check's recording step passes again

**Status:** ready-to-ship
**Branch:** subtle-catfish
**Open questions:** none

## Why

The iPhone check's recording step failed twice on #147, and the app was not the cause. On the first try, the step stopped at the *Get the speech model?* box. On the second try, the test iPhone took more than 2 minutes to write the words, and the alert *The words did not come* covered the note. Each later phone change that adds this step fails the same way until the step is fixed.

## What Changes

- **The step answers the speech-model box each time it shows.** Today the step taps *Get it* only once, just after *Record*. If the box comes later, or comes again, the step waits until it fails. Now the step taps *Get it*, *Allow* and *OK* each time they show while it waits for the recording screen. The checks are quick and do not wait.
  ```mermaid
  flowchart TD
    R["Tap Record"] --> Q{"What shows?"}
    Q -->|"a box"| B["Tap Get it, Allow or OK"]
    B --> R
    Q -->|"recording screen"| S["Save at once"]
  ```
- **The recording is shorter: about 10 seconds, not about 20.** After the recording screen shows, the step saves at once. A shorter recording gives the test iPhone less to write.
- **The step closes an alert and accepts each end of the words.** The step waits up to 3 minutes for the words. Then it taps *OK* on an alert such as *The words did not come*. It passes when the recording's card shows a *Transcript*, *No words heard*, or *The words did not come* with *Try again*. The picture shows which end came. The step still fails if the card does not show, or if typed words after it do not stay in the note.
  ```picture
  Before, the alert covers the note: pictures/before-words-did-not-come.png
  After, the card from this check: pictures/after-card.png
  ```
- **The phone app does not change.** The test iPhone has no fast speech chip, so it writes words slowly. A real phone does not have this problem.

## What the build needs

- **Nothing.** The step runs on GitHub's iPhone check, which the repository already has.

## Non-goals

- Make the speech model faster, or change the 2-minute limit for the words.
- Add the recording step to the fixed tour.
- Change the voice-note step (`voice-note.yaml`).

## Capabilities

### New Capabilities

### Modified Capabilities

None: only a tour step changes, not what the app or the check does (`skip_specs: true`).

## Impact

- Tour step: `mobile/device-check/flows/recording-card.yaml`.
- Wiki: `wiki/development/device-check-tour.md`, *Write a tour flow*, gets what this step taught: close a problem alert with *OK*, and check a box that may show with `runFlow` `when`, not an optional tap that waits.
- No app code, no server, no website page: the website does not describe the check's tour steps.
