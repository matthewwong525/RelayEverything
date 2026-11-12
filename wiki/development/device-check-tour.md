# The device check's tour

The tour is the part of [the device check](device-check.md) that runs Maestro flows on the iPhone with no AI, before Claude starts. [`tour.sh`](../../mobile/device-check/tour.sh) runs the fixed steps, `timeline`, `new-note`, `note-styles` and `settings`, then the check's extra steps, and writes `tour.json` and a picture of each step in `tour/`. It is part of [Development](README.md).

## A failed step runs once more

A step can fail on a working app: a slow Mac shows the words after a wait ran out, a tap misses, or Maestro's driver starts too late. So `tour.sh` runs each failed step again, alone, after it stops Maestro's driver and the app. The second try has 6 minutes, because it starts the driver again (up to 3 minutes, `MAESTRO_DRIVER_STARTUP_TIMEOUT`) and a step took up to 3 minutes on a slow Mac.

- **A step that passes on its second try counts as passed.** `tour.json` gives it `tries: 2`, and the report says *passed on the second try*. A step that needs it on check after check is worth a look: a retry can hide a rare fault, such as a race when the app starts.
- **A step that fails twice is broken.** The run ends before Claude, and the report names the step and shows its picture. When `timeline` fails twice, the app does not open, so the later steps get no second try.
- **Each step's picture shows its own screen.** A failed step shows Maestro's picture of the step where it stopped, from `maestro/<run>/<flow>/screenshots/`. A passed step shows its `takeScreenshot` named as the flow, else its newest one. A step that ran twice shows its second try's picture, else the first try's. Only a step with no picture from either try gets the screen after the tour, and `tour.json` marks it `screenshot_live: true`. Before, a failed `timeline` showed Settings, the last screen of the run.
- **A release gets the same second try.** The release gate reads `tour.json`, and a step that failed twice still stops a release.

## Extra tour steps

A check can name extra steps from [`flows/`](../../mobile/device-check/flows/), such as `voice-note`, with the input `flows` or `device-check.mjs --flows voice-note`. They run after the fixed steps, in the same Maestro run, with the same second try, pictures and verdict, only on that check. A release runs the fixed steps alone, and a label start has no inputs, so it does too. An unknown name ends the run as *could not check* before the build.

A phone change writes a step for its main path when the simulator can show it, and `/verify` names it: [the rule for the phone app](../../.agents/rules/mobile.md) says when. A step stays in `flows/` after its change ships. It joins the fixed tour only by a later choice, because each fixed step adds 1 to 2 minutes to every check and release.

## Write a tour flow

- **A tour step that fails with *iOS driver not ready in time* is Maestro's own start, not the app.** The driver now has 3 minutes to start, and the step runs once more. If it still fails twice, look at the step's picture in `tour/` and at the later steps to see if the app opened, then run the check once more or ask the person.
- **Prove a key flow in the fixed tour, not through Claude.** Each `maestro test` Claude starts by hand can stall for minutes, and its taps by screen position miss. A flow in [`tour.sh`](../../mobile/device-check/tour.sh) runs in seconds each time and also gates a release. *Aa* on the note page is checked this way, in `note-styles.yaml`.
- **A flow that needs more than the app stays out of the fixed tour.** `shortcut-note.yaml` needs the Shortcuts app, and `voice-note.yaml` needs the speech model, so a check names it as [an extra step](#extra-tour-steps). The fixed tour checks only what a fresh install shows, such as the *Hold to talk* tip in `new-note.yaml`.
- **A tour wait gives a screen 30 seconds to show its words**: a wait ends as soon as they show, so a fast run loses nothing. One slow runner showed each word after a 10-second wait ran out, and the check called a working app *broken*. Before you change the app, look at the step's picture in `tour/`: words on screen mean a slow runner.
- **A tour flow taps a button by its words or tooltip**, such as `tapOn: "Settings"` for Home's gear. A change that renames or removes a button the tour taps updates its flow in [`flows/`](../../mobile/device-check/flows/) in the same change, or every later check and release ends *broken*.
- **A step that passes on the second try is a missed tap or a slow Mac, not a stale flow.** For example, `new-note` once failed at *Cancel*: Maestro tapped Search and the app opened nothing, and the runs before and after passed. The second try now catches this; change a flow only when it fails twice.
- **A row low on Home sits under Search and New note**: scroll it to the middle (`scrollUntilVisible` with `centerElement: true`) before a tap, or the tap opens the search box.

**Match a Flutter row by the start of its text.** Flutter joins a card's lines, or a row's title and its small text, into one label, such as `Sign in to Relay Everything\nYour notes stay…`. Maestro matches the whole label, so `assertVisible: "Sign in to Relay Everything"` fails. Write `assertVisible: 'Sign in to Relay Everything(.|\n)*'`, in single quotes. A line in the middle of a label, such as *Tap anywhere to save* in the recording screen's `Listening\n0:34\nTap anywhere to save\n…`, needs `(.|\n)*` on both sides: `'(.|\n)*Tap anywhere to save(.|\n)*'`. A failed flow keeps its screen's labels in `maestro/<flow>/…/screen-hierarchy/`, in the run's results.

**Check that a word is gone by its own label, not the whole screen.** Maestro ignores upper and lower case, so `assertNotVisible: '(.|\n)*On this phone(.|\n)*'` also fails on the empty list's hint *Notes stay on this phone…*. Match the whole label you mean instead, such as `assertVisible: 'Notes\nNo notes'` for the Notes title and its count: a whole-label match proves no other word is in that line. Before the first device check of a change that edits screen words, read each `assertVisible` and `assertNotVisible` in `flows/` for the old words: each wrong step costs a check of about 30 minutes.

**A tap that opens the wrong thing can mean a label's box is too big.** Maestro taps the middle of the label's box. A Flutter `Semantics` with no `container: true` joins its parent's node, so its box can cover the rows below: on 2026-11-12 a tap on the *Pinned* heading opened the note under it, because the heading's box held the card too. VoiceOver gets the same wrong box, so fix the app, not the flow: give that `Semantics` `container: true`. The `bounds=` of each tap in `maestro.log` shows the box.

**Never use `waitForAnimationToEnd` on a screen with a blinking cursor.** The cursor never stops, so the step never ends: on 2026-11-11 a check of the note editor's text menu stopped at its time limit with no report. Wait for words with `extendedWaitUntil`, or take the picture at once.

**Never use `hideKeyboard`.** The Flutter app's keyboard has no dismiss action that Maestro can use, so the step fails with *Couldn't hide the keyboard* and the flow ends *broken*. After `inputText`, tap the next button at once, such as `tapOn: "Save"` on the webhook form: the form keeps its buttons above the keyboard.

**Tap an icon button by its label.** A button with no words on the screen, such as the round *New note* or the ⋯ button, has an accessibility label or a tooltip. Maestro matches it as it matches text: `tapOn: "New note"`, `tapOn: "More"`. A Maestro tap is short, so `tapOn: "New note"` opens the *New note* page and never records.
