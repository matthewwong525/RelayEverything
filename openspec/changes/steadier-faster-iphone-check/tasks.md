# Tasks

## 1. Tour: retry, stop before Claude, right pictures

- [x] 1.1 Take main after PR #75 lands (or build on it), so the 30 s waits and `voice-note.yaml` are in; verify `git log` shows #75's merge. (Done: the branch is on main at fe36e36, with #75 as 6bc6a3b and #78.)
- [x] 1.2 Move `flow.sh`'s limited run into a shared function both `flow.sh` and `tour.sh` use; verify `flow.sh` still prints `result=` on a dry run with a stub `maestro`.
- [x] 1.3 In `tour.sh`, re-run each failed flow alone after stopping `maestro-driver` and the app; `ok=true` only when every flow passed; `broken.sh` names the failed steps. Set `MAESTRO_DRIVER_STARTUP_TIMEOUT=180000`. Verify with a stub `maestro` that fails a flow once (passed, `tries: 2`) and twice (broken).
- [x] 1.4 In `tour-json.mjs`, merge the second try into `tour.json` (`tries`, `screenshot_live`); pick each flow's own picture by design.md. Extend `tour-json.test.mjs` for both, and run it.
- [x] 1.5 In `finish.sh`, show *passed on the second try* beside such steps; verify on a sample `out/` folder.

## 2. Crashes

- [x] 2.1 Add `mobile/device-check/crash.mjs` and `crash.test.mjs` with a saved sample `.ips` (no personal data); verify the test reads the exception, signal and first 8 frames.
- [x] 2.2 Start the crash watcher in `iphone-open.sh`, stop it with the video; `finish.sh` puts *The app crashed* first and makes the verdict `broken`. Verify on a sample `out/` with a crash file.
- [x] 2.3 In `brief.md` and `iphone.md`, tell Claude to read `out/crashes/` when the app leaves the screen; verify `brief.sh` output holds it.

## 3. Extra tour steps and the early result

- [x] 3.1 Add the `flows` input to `mobile-device-check.yml`, its name check in *Check the commit*, and pass it to `tour.sh`; never with `tour_only`. Validate with `npx --yes @action-validator/cli`.
- [x] 3.2 Upload `device-check-tour` after the tour; add job `tour-report` by design.md. Validate the workflow.
- [x] 3.3 In `scripts/device-check.mjs`, add `--flows`, and print `tour=` and `tour_reason=` once the tour file appears; tests in `scripts/device-check.test.mjs`.

## 4. Re-check

- [x] 4.1 In `scripts/device-check.mjs`, add `--recheck`: find the last finished check, parse its scenario verdicts, filter the scenarios file, send `passed_before`; print `recheck=` lines. Tests on a saved report and scenarios file, including no earlier check and an unmatched name.
- [x] 4.2 Add the `passed_before` input and *Passed in the last check* in `finish.sh`; verify on a sample `out/`.

## 5. Build cache

- [x] 5.1 Add the cache and the clean rebuild on a failed cached build to *Build for the simulator*; validate the workflow.

## 6. Docs and rules

- [x] 6.1 Update `.agents/rules/mobile.md`: run the script in the background with `--recheck`, tell the person `tour=`, name the change's flow with `--flows`, write a flow for a change's main path, and `Scenario:` blocks in the scenarios file.
- [x] 6.2 Update `wiki/development/device-check.md`: the retry, a failed step stops Claude, crashes, the early note, extra steps, re-checks, the cache and the run time.

## 7. Checks

- [x] 7.1 Run `node --test scripts/device-check.test.mjs mobile/device-check/*.test.mjs`, the workflow validator and `node scripts/public-check.mjs`; fix what fails.
- [ ] 7.2 `/save`, then start a check on the saved commit with `--flows voice-note`: the pull request gets the tour note at about 15 min, the voice-note step runs in the tour, and the full report follows. Log the times and the build time.
- [ ] 7.3 Start 2 more checks, the second with `--recheck`: compare the 3 build times (keep the cache only at 2 min saved or more), and confirm the re-check sends only what was not *works*. Log the results in the Decision log.
