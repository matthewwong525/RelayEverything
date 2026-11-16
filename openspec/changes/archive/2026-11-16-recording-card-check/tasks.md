# Tasks

## 1. Tour step

- [x] 1.1 `mobile/device-check/flows/recording-card.yaml`: drop the one-time `runFlow` for *Get it*; in the `repeat` loop, check *Get the speech model?* → *Get it*, `Allow` → *Allow*, `OK` → *OK*, then *Record*, each with `runFlow` `when: visible`, then the 5 s optional wait, as design.md says. Update the comments above it.
- [x] 1.2 Same file: after the loop, drop the optional `tapOn: "Allow|OK"` and the second wait for *Tap anywhere to save*; tap `50%,50%` at once.
- [x] 1.3 Same file: wait up to `180000` ms for *Writing the words…* to go; then a `when: visible: "OK"` tap; then `assertVisible: '(.|\n)*(Transcript|No words heard|The words did not come)(.|\n)*'` before the picture; add one more `when: visible: "OK"` tap before the last `tapOn: "Fab call"`. Update the top comment: the card shows a transcript, *No words heard*, or *The words did not come* with *Try again* on a slow test iPhone.

## 2. Wiki

- [x] 2.1 `wiki/development/device-check-tour.md`, *Write a tour flow*: add a line that a phone problem shows as an alert with *OK* (since #139), so a flow taps *OK* before its next tap; and a line that a box that may show is checked with `runFlow` `when: visible`, which does not wait, not an optional `tapOn`, which waits before it gives up (on #147 that wait made a recording 19 s long). Keep the page under 3,000 words.

## 3. Checks

- [x] 3.1 Check the YAML parses: `node -e` with a YAML parser, or `npx --yes js-yaml mobile/device-check/flows/recording-card.yaml`.
- [x] 3.2 Run `/save`, then run the device check on the saved commit with `--flows recording-card`. Pass: `tour.json` shows `recording-card` passed, and `tour/recording-card.png` shows the recording's card with no alert. Read the step's times in `maestro.log`; if a wait ran close to its timeout, raise it and check once more. Done: run 43958043942, `recording-card` passed on its first try; the picture shows the card, a 0:10 recording with *The words did not come. Your recording is safe.* and *Try again*, and no alert. The whole tour fit its limits on the first try, so no timeout changed.
