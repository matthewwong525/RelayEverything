# Proposal: A steadier, faster iPhone check

**Status:** in-progress
**Branch:** fix-iphone-check
**Open questions:** none

## Why

The iPhone check often fails when the app is fine, and a real problem takes about 30 minutes to show. Since 2026-11-06, 8 of about 35 checks failed. Only 2 were app bugs (the voice note crash on PR #75). At least 4 were the check itself: a slow iPhone, a tap that missed, and Maestro not ready in time. Each false failure costs another 30-minute run. The PR #75 crash was found only by Claude, at the end, after many turns spent guessing whether the app had crashed.

## What Changes

- **A failed tour step runs once more before it counts.** The tour runs as now. Each step that failed then runs again, alone, after the iPhone's tap driver restarts. A step that passes the second time counts as passed, and the report marks it *passed on the second try*, so a step that does this often gets noticed. A step that fails twice is broken: the check ends there, and Claude does not start, so a sure failure takes about 15 minutes, not 30. Each step's picture shows the screen where that step stopped, not the last screen of the run.
  ```text
  Before                          After
  tour: timeline  failed          tour: timeline  failed
        -> broken (false alarm)         again     passed
                                  -> passed on the second try
  ```
- **A crash is named at once.** When the app crashes, the report says *The app crashed* first, with the crash's reason and its first lines of code. Claude can read the crash report while it works, so it stops guessing and moves on to the next scenario.
  ```text
  ## iPhone check: broken

  The app crashed: EXC_BREAKPOINT (SIGTRAP)
    0 Flutter  ... MTLDevice newLibrary
    1 sherpa   ... loadModel
  ```
- **The tour's result comes back first.** As soon as the tour ends, at about 15 minutes, the pull request gets a short note and `/verify` tells you: the tour passed and Claude is checking now, or the tour is broken and why. The full report follows as today.
  ```mermaid
  sequenceDiagram
    participant V as "/verify"
    participant M as Mac on GitHub
    participant P as Pull request
    V->>M: start the check
    M-->>P: tour: passed (~15 min)
    M-->>V: tour: passed
    M-->>P: full report (~25-30 min)
    M-->>V: full report
  ```
- **A change's main path runs in the tour, with no AI.** A check can name extra tour steps from `mobile/device-check/flows/`, such as the voice note's hold, tap to save and cancel. They run with the fixed tour, the same way each time, with a retry too. A change to the phone app writes such a step for its main path when the simulator can show it. Claude then only looks at what a fixed step can't. The PR #75 crash would have shown at about 15 minutes, with no AI.
  ```text
  every check and release:
    timeline  new-note  note-styles  settings
  this check only:
    + voice-note
  ```
- **A re-check tries only what did not work.** After a fix, `/verify` gives Claude only the scenarios that were broken or not checked in the last check of the same branch. Each one that passed is listed as *passed in the last check*, with that check's link. The tour still runs in full. This saves about 5 to 10 minutes for each re-check.
- **The app builds faster.** The check keeps the iPhone build's slow parts between runs, so a build does not start from nothing. This stays only if three runs show it saves at least 2 minutes. Else it is taken out again.

Non-goals: an Android device check; a check that starts on each save; a change to the release gate's steps (it gets the retry, and a step that fails twice still stops a release).

## What the build needs

- **Nothing.** The work runs on GitHub's free Macs and the existing Claude token.

## Decision log

- **2026-11-09** — Asked which fixes the plan should include → chose all four: retry a failed tour step and name crashes, the tour's result first, a change's main path in the tour, and a faster build by keeping its parts between runs.
- **2026-11-09** — Asked what a tour step that fails, then passes on its second try, should give → chose pass, marked *passed on the second try* in the report.
- **2026-11-09** — Asked whether a re-check after a fix should skip what passed → chose only the scenarios that were broken or not checked last time; the tour still runs in full.
- **2026-11-09** — Assumed: a tour step that fails twice ends the check as broken before Claude starts, because a sure failure needs no AI, and today Claude spends 15 minutes after a failed `new-note` step for a verdict that is already *broken*.
- **2026-11-09** — Assumed: the release gate gets the same retry, because the release spec stops a release on a failed tour step, and a step that fails twice is still one; a slow Mac should not stop a release.
- **2026-11-09** — Assumed: the early note on the pull request comes from a separate job on GitHub's Linux machine that waits for the tour's results file, because the Mac job has no write token by design, and that job runs no branch code.
- **2026-11-09** — Assumed: the build cache stays only if it saves at least 2 minutes in 3 runs, because a cache of Xcode's build folder between Macs may not help, and an unhelpful cache only adds upload time.
- **2026-11-09** — Assumed: this plan builds after PR #75 lands, or takes main when it does, because #75 changes the same tour steps (30-second waits) and adds `voice-note.yaml`, the first extra step this plan runs.
- **2026-11-09** — Evidence: on run 42544862299, the failed `timeline` step's own picture shows *No notes yet* on the screen, the same commit's code passed on run 42541088405, and the tour took 10 min 22 s against 5 min 44 s, so the failure was a slow Mac, not the app. The report's `timeline.png` showed Settings, because `tour.sh` fell back to the last screen.
- **2026-11-09** — Assumed: a second try has 6 minutes, not the 120 s of `flow.sh`, because it starts Maestro's driver again (up to 180 s) and a passing `timeline` took 145 s on a slow Mac (run 42503040787); 120 s would fail a working app. The two share one function, `limit.sh`.
- **2026-11-09** — Assumed: when `timeline` fails on both tries, the later failed steps get no second try, because the app did not open and each try would add up to 6 minutes.
- **2026-11-09** — Assumed: a crash during the tour ends the check as broken before Claude, as a step that fails twice does, because a crash makes the verdict broken whatever Claude finds.
- **2026-11-09** — Assumed: the build cache keeps `mobile/build/ios` and Xcode's `DerivedData`, keyed by the Mac image, the Flutter version and `pubspec.lock`, because the app uses Swift packages and has no `Podfile.lock` or `Pods/`. It saves right after a good build (`actions/cache/save`), so a check that ends broken still saves it.
- **2026-11-09** — Assumed: `--recheck` sends every scenario, with `recheck=none`, when each scenario worked last time or no name matches, because an empty scenarios input makes Claude read the open specs instead.
- **2026-11-09** — Assumed: the wiki's device check page went over 3,000 words, so its tour parts moved to a new page, `wiki/development/device-check-tour.md`.
- **2026-11-09** — Evidence: the crash test's sample `mobile/device-check/crash.sample.ips` is cut from run 42537544439's `Runner-2026-11-09-002231.ips` (the PR #75 Metal crash), with only the exception, termination, the crashed thread's first 12 frames and image names; no paths, IDs or device names.
- **2026-11-09** — Check: `.github/workflows/mobile-device-check.yml` a failed save of the build cache does not fail the job (`continue-on-error`), and a failed tour step runs once more before it counts, because the cache only saves time and a slow Mac or a missed tap should not fail a working app.
- **2026-11-09** — Assumed: a re-check carries forward the scenarios an earlier re-check skipped as passed, and reads the newest check that reached Claude, because a re-check's own report holds only what it tried, and the plan's goal is less Claude time for each re-check.
- **2026-11-09** — Built inside /ship; the second look found 2 problems (a step's first-try picture lost when its second try left none, and a re-check that sent earlier passes again from the second re-check on), both fixed. Saved for the live checks (tasks 7.2 and 7.3).

## Capabilities

### New Capabilities

### Modified Capabilities
- `relay-app-device-check`: a failed tour step runs once more; a step that fails twice ends the check before Claude; a check can add tour steps; crashes are named; the tour's result comes back first; a re-check tries only what did not work.

## Impact

- `mobile/device-check/tour.sh`, `tour-json.mjs` (+ test): retry failed flows one by one after a driver restart, `tries` in `tour.json`, extra flows, each flow's own failure picture.
- New `mobile/device-check/crash.mjs` (+ test): summary from `.ips` crash reports; a watcher in `iphone-open.sh` that copies new reports to `out/crashes/` as they appear; `finish.sh` and `brief.md` use them.
- `.github/workflows/mobile-device-check.yml`: `flows` input, a tour-only artifact `device-check-tour`, a new `tour-report` job, end before Claude on a failed step, `MAESTRO_DRIVER_STARTUP_TIMEOUT`, cache of Pods and the build folder.
- `scripts/device-check.mjs` (+ test): `--flows`, `--recheck`, print `tour=` early.
- `.agents/rules/mobile.md`, `wiki/development/device-check.md`, and the `/apply` rule for a change's tour step.
