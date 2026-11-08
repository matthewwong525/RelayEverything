# Tasks

## 1. Mobile CI

- [x] 1.1 In `.github/workflows/mobile-ci.yml`, add `android-branch` and `ios-branch` (`needs: plan`, `mode == 'branch'`) and limit `android` and `ios` (`needs: [plan, flutter]`) to the other modes, by design.md.
- [x] 1.2 In `.github/workflows/mobile-android.yml`, build `--target-platform android-arm64` for `mode == branch`; find where the speech package's native objects go, and cache them and Gradle's build cache with `actions/cache`, keyed by `mobile/pubspec.lock` and the Flutter version.
- [x] 1.3 In `.github/workflows/mobile-ios.yml`, replace the full `flutter build ios` with `flutter build ios --config-only`, keeping version and build number.
- [x] 1.4 Update `scripts/app-release.test.mjs` or the workflow tests that read job names in `mobile-ci.yml`, if any; add a test that a branch build job does not need `flutter` and a beta/release build job does.

## 2. Device check: speed

- [x] 2.1 Split `mobile/device-check/iphone-open.sh` into `iphone-boot.sh` (pick, boot in the background, `DEVICE_UDID`) and `iphone-open.sh` (wait, install, video, launch); run the boot before *Build for the simulator*.
- [x] 2.2 Rewrite `mobile/device-check/tour.sh` to run the three flows in one `maestro test` with JUnit output and build `tour.json` from it in today's shape; fall back by design.md if Maestro will not.
- [x] 2.3 Move *Swift tests* into a new `swift-tests` job in `.github/workflows/mobile-device-check.yml`, with its own artifact; `report` and the release gate read its result.
- [x] 2.4 Add the job concurrency to `iphone` and `swift-tests`, never cancelling a `tour_only` run.

## 3. Device check: Claude

- [x] 3.1 Add `mobile/device-check/flow.sh` (90 s limit, kill and one retry, `result=` line).
- [x] 3.2 Set `--max-turns 80` and the new `allowedTools` in the Claude step, by design.md.
- [x] 3.3 Update `mobile/device-check/brief.md` (write the report first, update after each scenario, 60 tool calls) and `iphone.md` (use `flow.sh`).
- [x] 3.4 Add the step-log step: `out/claude/steps.md` and `out/claude/end.txt` from the action's `execution_file`, in a small node script `mobile/device-check/steps.mjs` with a test beside it on a saved sample.
- [x] 3.5 Update `mobile/device-check/finish.sh` for the `no-verdict` verdict, its reason and exit 1; keep Claude's own `could-not-check` green.
- [x] 3.6 Teach `scripts/device-check.mjs` the `no-verdict` and `cancelled` results, with tests in `scripts/device-check.test.mjs`; map them in `.agents/rules/mobile.md` (`no-verdict` and `cancelled` are UNKNOWN, with the reason).

## 4. Docs

- [x] 4.1 Update `wiki/development/device-check.md`: the steps, the verdict table (`no-verdict`), the second Mac, the step log, the turn limit and the run time.
- [x] 4.2 Update `mobile/README.md#builds-on-github` for the branch builds that start with the tests and the arm64-only branch file.

## 5. Checks

- [x] 5.1 Run `node --test scripts/*.test.mjs`, the device-check script tests, `actionlint` if present, and `node scripts/public-check.mjs`; fix what fails.
- [ ] 5.2 `/save`, then confirm on GitHub: Mobile CI on the branch starts both builds with the tests and ends in about 6 minutes or less; the Android file and the iPhone archive still build.
- [ ] 5.3 Start the device check on the saved commit twice in a row: the first is cancelled, the second gives a verdict (any of works, broken, could-not-check) in about 20 minutes, `claude/steps.md` is in the run's files, and the Swift tests ran on the second Mac. Record the times in the Decision log.
