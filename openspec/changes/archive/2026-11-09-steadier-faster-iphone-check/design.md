# Design

## Context

See proposal.md, Why. Today's check ([`wiki/development/device-check.md`](../../../wiki/development/device-check.md)) runs on one Mac: boot, build (about 9 min), open, a one-run Maestro tour of 4 flows (`tour.sh`, 5 to 10 min), then Claude (up to 20 min). A second Mac runs the Swift tests. `tour.sh` gives `ok` when `timeline` passes, so Claude still runs after another step fails. Crash reports reach `out/crashes/` only in `finish.sh`, after Claude ends. The Mac job has no write token; job `report` posts on the pull request after both Mac jobs end.

Failures since 2026-11-06 that were not the app: `iOS driver not ready in time` (run 42494210887), a missed tap on *Cancel* (42503040787), Claude's taps not reaching the screen (42443062518), and a slow Mac past a 10 s wait (42544862299, whose `timeline` picture shows the words it asserted).

## Goals / Non-Goals

**Goals:** a one-off failure of the check never fails it; a sure failure ends in about 15 min; a crash names itself; the tour's result shows at about 15 min; a re-check after a fix costs less Claude time.

**Non-Goals:** a faster Claude per scenario; changing the release spec's list of gates; an Android check.

## Decisions

### Retry failed flows one by one, after a driver restart

`tour.sh` keeps the one Maestro run for all flows (fast when all pass). For each flow that failed, it stops `maestro-driver`, terminates the app, and runs that flow alone through the same 120 s limit as `flow.sh` (share the function, don't copy it). `tour.json` gets `tries: 1|2` per flow; `tour-json.mjs` merges the second try's result. Set `MAESTRO_DRIVER_STARTUP_TIMEOUT=180000` for the tour and Claude, for the driver failure on run 42494210887.

Alternative: run the whole tour twice. Rejected: it doubles 5 to 10 min to fix one step.

### Any step failed twice ends the check before Claude

`tour.sh` gives `ok=true` only when every flow passed (on either try); else `broken.sh` names the failed steps. Claude's step then skips, as for a failed `timeline` today. The release gate already reads `tour.json`; a flow with `passed: true, tries: 2` passes it.

### Each flow's own picture

For a failed flow, take the newest picture under `maestro/<run>/<flow>/screenshots/`; for a passed one, its `takeScreenshot` with the flow's name. Fall back to a live screenshot only when the flow left no picture, and say so in `tour.json` (`screenshot_live: true`). Today's fallback put the run's last screen (Settings) in `timeline.png`.

### Crashes: copy as they happen, summarise in code

`iphone-open.sh` starts a background loop (pid in `$RUNNER_TEMP`, stopped with the video) that copies each new `~/Library/Logs/DiagnosticReports/Runner*.ips` to `out/crashes/` every 5 s. New `crash.mjs` reads an `.ips` (a JSON header line, then a JSON body) and writes `out/crash.txt`: the exception type and signal, the termination reason, and the crashed thread's first 8 frames as `image symbol`. A test reads a saved sample `.ips`.

- `finish.sh` puts `crash.txt` first in `report.md`, under *The app crashed*, and a crash makes the verdict `broken`: an app that crashes is broken whatever a step showed.
- `brief.md`: when the app leaves the screen, read `out/crashes/`; a file there means a crash: write the scenario as broken with the crash's first lines, then go on. Claude already has `Read` and `Glob`; no new command.

### The tour's result, early, with no write token on the Mac

After the tour, the Mac job uploads `device-check-tour` (`tour.json`, `tour/`, `reason.txt`, `crash.txt`). Artifacts from `upload-artifact` v4 can be downloaded while the run still goes.

- New job `tour-report` on `ubuntu-latest`, with no `needs`, `pull-requests: write`, only for a run with a pull request. It checks out no code; it asks the run's artifacts each 30 s, up to 40 min, for `device-check-tour`, then posts one short note: tour passed (with the steps that needed a second try) and Claude is checking, or the tour is broken, with the reason. It stops with no note if the Mac job ends first with no tour file.
- `scripts/device-check.mjs` asks for the same artifact while it waits, and prints `tour=passed|broken` and `tour_reason=` once. The rule for `/verify` runs the script in the background and tells the person the `tour=` line when it shows.

### Extra tour steps by name

New `workflow_dispatch` input `flows`: names split by spaces. The *Check the commit* step checks each against `^[a-z0-9-]+$` and `mobile/device-check/flows/<name>.yaml`; an unknown name ends the run as `could-not-check` before the build. `tour.sh` runs the fixed 4, then the extras, in the same Maestro run, with the same retry. `tour_only` (the release) never passes `flows`. `device-check.mjs` takes `--flows a,b`. A label start has no inputs, so it runs the fixed tour only.

The rule in `.agents/rules/mobile.md` says: a phone change writes a flow for its main path in `mobile/device-check/flows/` when the simulator can show it (no microphone sound, no health, no server), and `/verify` names it. A flow stays in the folder after the change ships; it joins the fixed tour only by a later choice, because each fixed step adds 1 to 2 min to every check and release.

### Re-check: only the scenarios that were not *works*

`device-check.mjs run --recheck` (the `/verify` rule passes it):

1. Finds the newest finished, not cancelled check of `--ref` started by hand (`gh run list`), and downloads its `claude/report.md`.
2. Reads each `Scenario:` block and its `Verdict:` (one parser, beside `readVerdict`, with a test on a saved report).
3. Splits the scenarios file into blocks by its `Scenario:` lines; drops each block whose name matches, case and spaces aside, a `works` scenario. A block it can't match stays.
4. Sends the rest as `scenarios`, and the dropped names with the run's link as new input `passed_before`. `finish.sh` adds *Passed in the last check* with that list.

With no earlier check, or a report it can't read, every scenario goes, and the script prints `recheck=none` with the reason. The scenarios file format is already `Scenario: <name>` blocks with WHEN and THEN (the rule writes it); the rule says so.

### Build cache, kept only if it pays (taken out: it saved about 1 minute)

`actions/cache` for `mobile/ios/Pods`, `~/Library/Caches/CocoaPods` and `mobile/build/ios`, keyed by the runner image version, the Flutter version, `pubspec.lock` and `Podfile.lock`, with a restore key that drops the lock files. If the build fails with a restored cache, delete `mobile/build/ios` and build once more, so a bad cache never fails a check. Measure the *Build for the simulator* time on 3 runs against today's 7.5 to 9.5 min; keep the cache only if it saves at least 2 min, else take it out in the same change and log the times.

## Risks / Trade-offs

- [A retry hides a real, rare app fault, such as a race on start] → the report marks each second try, and `/verify` shows it; a step that needs it twice in a row on a branch is worth a look.
- [The early note adds a second comment to the pull request] → it is one short line, and the full report follows; a cancelled run posts neither.
- [`tour-report` polls for up to 40 min on Linux] → free for a public repository; it ends as soon as the Mac job ends.
- [A re-check skips a scenario the fix broke] → the tour still runs in full, and the `/verify` rule adds back any scenario whose screen the fix touched; the full check runs again before ship if the person asks.
- [PR #75 changes the same flows] → build after #75 lands, or take main when it does.

## Migration Plan

No data. Roll back by reverting the change; old runs keep their files.
