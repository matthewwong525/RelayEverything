# Design: the iPhone check's recording step passes again

## Context

`mobile/device-check/flows/recording-card.yaml` is an extra tour step (`--flows recording-card`), added by #144. It passed once, on run 43811959229 (a 0:18 recording, transcript *you*). It failed on both tries on #147's check, run 43883673332:

1. **Try 1:** the screen stayed on *Get the speech model?*. The flow taps *Get it* in one `runFlow` `when: visible`, checked once, right after the first *Record*. The `ModelDialog` (`mobile/lib/screens/hold_to_talk.dart`) comes in with an animation, so the check can run before it shows. The model can also come back to *missing* after a failed download, and *Record* then asks again. The `repeat` loop below taps only *Record* and `Allow|OK`, never *Get it*, so it runs out its 40 tries behind the box.
2. **Try 2:** the recording saved at 0:19. Then whisper.cpp on the simulator ran past `wordsLimitOf` (2 minutes for a short recording, `mobile/lib/controller.dart`). `_write` marks the words failed and calls `notice(_wordsDidNotCome)`. Since #139 a notice is `showProblem` (`mobile/lib/screens/folder.dart`): a `CupertinoAlertDialog` with *OK* over the root navigator. The flow's next `tapOn: "Fab call"` hit the alert's barrier and failed.

Both recordings were about 19 s long. After the recording screen shows, the flow runs an optional `tapOn: "Allow|OK"`. Maestro waits for the element of an optional tap before it gives up, so the microphone records for all of that wait. A longer recording gives whisper more audio to write on a slow runner.

## Goals / Non-Goals

**Goals:** the step passes on a slow runner, and it still fails when the recording card or the typed words do not show.

**Non-goals:** app changes; the 2-minute words limit; `voice-note.yaml`; the fixed tour.

## Decisions

### Check boxes with `runFlow` `when`, inside the wait loop

Each loop pass:

```yaml
- runFlow:
    when: { visible: "Get the speech model?" }
    commands: [ { tapOn: "Get it" } ]
- runFlow:
    when: { visible: "Allow" }
    commands: [ { tapOn: "Allow" } ]
- runFlow:
    when: { visible: "OK" }
    commands: [ { tapOn: "OK" } ]
- runFlow:
    when: { visible: "Record" }
    commands: [ { tapOn: "Record" } ]
- extendedWaitUntil:
    visible: '(.|\n)*Tap anywhere to save(.|\n)*'
    timeout: 5000
    optional: true
```

A `when` check reads the screen once and does not wait, so a pass costs about 5 s at most. *Allow* is a whole-label match, so it never matches iOS's *Don't Allow*. *OK* closes *The speech model is still coming* (a `showProblem` alert since #139) and the older microphone alert. The *Record* tap goes last, after each box is closed: a box covers *Record*. Keep the first *Record* tap before the loop and drop the one-time `runFlow` for *Get it*: the loop covers it.

The loop keeps `times: 40`. With the model download (`voice-note.yaml` gives it 100 s) and about 5 s a pass, 40 passes is more than 3 minutes.

*Alternative:* optional `tapOn` for each box in the loop, as today. Rejected: each optional tap waits before it gives up, so a pass takes far longer, and the same wait makes the recording long.

### Save the recording at once

After the loop, drop the optional `tapOn: "Allow|OK"` and the second `extendedWaitUntil`; the loop exit already proves *Tap anywhere to save* shows. Tap `50%,50%` at once. The recorder keeps a recording of 0.5 s or more (`shortest` in `mobile/lib/voice/recorder.dart`), and the loop's last wait plus Maestro's own step time pass that.

### Wait 3 minutes for the words, then close the alert

```yaml
- extendedWaitUntil:
    notVisible: "Writing the words…"
    timeout: 180000
- runFlow:
    when: { visible: "OK" }
    commands: [ { tapOn: "OK" } ]
- assertVisible: '(.|\n)*(Transcript|No words heard|The words did not come)(.|\n)*'
- takeScreenshot: recording-card
```

The app gives up on the words at 2 minutes, so 3 minutes always sees an end. The alert comes at that end, so the `OK` check goes after the wait. The `assertVisible` proves the recording's card shows one of its three ends; *The words did not come* comes with *Try again* on the card (`note_blocks.dart`). The rest of the flow, the transcript tap and the typed words, stays as it is. Before the last `tapOn: "Fab call"`, add one more `when: visible: "OK"` check, because a late alert can still come.

*Alternative:* tap *Try again* when the words fail. Rejected: it adds up to 2 more minutes, and a slow runner fails again the same way.

Time budget for a second try: `tour.sh` stops a second try at 360 s, and that time also holds the restart of Maestro's driver, up to 180 s on a slow Mac. A first try downloads the model, so the second try starts with it; then it needs about 30 s to open and record, up to 2 minutes of words, and its taps. A second try with a slow driver and slow words can still run over: task 3.2 reads the times in `maestro.log`, and only that evidence raises `RETRY_LIMIT`.

Before the picture, a 3 s optional wait for *OK* lets the alert show: the app changes the card first, then shows the alert. The card check matches *The words did not come. Your recording is safe*, the card's own words, not the alert's title.

## Risks / Trade-offs

- **The step can pass with no words written.** The card and its *Try again* still prove the recording went into the note; the picture shows which end came, and Claude's check of the change looks at words. A real transcript stays the job of the unit tests and a real phone.
- **A `when: visible: "OK"` could match another *OK*.** On the note page, only an alert shows *OK*, so a tap closes only an alert.
- **One device check costs about 30 minutes**, and the step's timings come only from a GitHub Mac. Read the step's `maestro.log` times after the first run; change a timeout only on that evidence.

## Decision log

- **2026-11-16** — Assumed: change only the flow, not the app, because the request settled it unless the app is truly wrong, and the failures come from a slow simulator (the same app passed on run 43811959229).
- **2026-11-16** — Assumed: the step passes when the words fail on the test iPhone, after it closes the alert, because the request says to close the alert and the step proves the card, not the speech engine.
- **2026-11-16** — Assumed: save the recording at once, because the long optional tap made both recordings about 19 s, and less audio means less to write.
- **2026-11-16** — Assumed: no spec change (`skip_specs: true`), because a tour step is how the check runs, not what it promises.
- **2026-11-16** — Assumed: add two lines to the wiki's *Write a tour flow*, because a later flow meets the same alert and optional-tap wait.
- **2026-11-16** — Assumed: keep `tour.sh`'s 360 s second-try limit and rely on task 3.2's timing check, because raising it changes a file the plan does not name and the driver's 180 s start is a worst case.
- **2026-11-16** — Saved for the device check (task 3.2); the second look's fix makes the card check match the card's own words, not the alert's title.
- **2026-11-16** — Device check run 43958043942: `recording-card` passed on its first try. The words still ran past 2 minutes on the test iPhone, and the step closed the alert as planned. The recording was 0:10, not a few seconds: the loop's checks take time after the last *Record* tap.
- **2026-11-16** — Archive checkpoint: archived for publish on branch subtle-catfish.
