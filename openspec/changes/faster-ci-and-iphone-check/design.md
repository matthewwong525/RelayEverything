# Design

## Context

Measured on GitHub on 2026-11-07 and 2026-11-08:

| Run | Step | Time |
|---|---|---|
| Mobile CI 42493640409 (branch) | `flutter` (analyze, test) | 1 min 18 s |
| | `android / apk`, Build step | 6 min 35 s, after `flutter` |
| | `ios / testflight`, Build + Sign and check | 3 min 46 s + 3 min |
| Device check (6 runs) | Build for the simulator | 3-4.5 min |
| | Open the app (boot, install) | 3-8 min |
| | Fixed tour (3 Maestro runs) | 5-11 min |
| | Claude tries the change | 0.5-14 min |
| | Swift tests (`xcodebuild test`) | 4-11 min, a second full build |

Only `test` (test.yml) is a required check on `main`; Mobile CI and the device check are not.

Device-check failures:

- 42342296015: a real app fault (*Unable to run App Shortcut*). The check did its job.
- 42276945382, 42443062518: a tour step was out of date with a changed screen (`settings.yaml` asserted *Send my notes* after the branch moved it). Real test drift, found late.
- 42443062518 also: Claude's `maestro test` hung past 120 s three times.
- No verdict, green: 42488574264 (8 turns in 20 s, `permission_denials_count: 4`, no report), 42451303657 (12.5 min, pictures but no report: `--max-turns 40` ran out), 42424382478. The action hides output (`show_full_output: false`), and the execution file in `$RUNNER_TEMP` is not kept, so the refused commands can't be seen today.

## Goals / Non-Goals

**Goals:** shorter wall time for Mobile CI and the device check with no test removed; Claude finishes or the check says why it did not; the refused commands are visible.

**Non-Goals:** fewer builds; changing required checks; new tour steps; an Android device check.

## Decisions

### Mobile CI: branch builds start with the tests

GitHub `needs` cannot be conditional, so each build gets two jobs that call the same reusable workflow:

- `android-branch`, `ios-branch`: `needs: plan`, `if: needs.plan.outputs.mode == 'branch' && github.event_name != 'pull_request'`.
- `android`, `ios`: `needs: [plan, flutter]`, `if: mode != 'branch' && github.event_name != 'pull_request'`. `release` keeps `needs: [plan, android, ios, tour]`.

A failed `flutter` job still makes the run red. A branch publishes nothing, so a build that finishes before a failed test does no harm. Alternative: keep one job and gate only the publish steps on test results inside the reusable workflow; rejected because it needs the test result passed in as an input and splits the gate across files.

### Android: arm64 only on a branch, and keep the speech build

- `mode == branch`: `flutter build apk --release --target-platform android-arm64`. Main and releases build every ABI. The file name stays the same.
- Cache the CMake output of `whisper_cpp_flutter_plus` (the plugin's `.cxx` folder under `mobile/build/` and `android/app/.cxx`) and Gradle's build cache with `actions/cache`, keyed by `mobile/pubspec.lock` and the Flutter version. Apply measures which folder holds the native objects before it fixes the paths.

### iPhone build: compile once

`mobile-ios.yml` runs `flutter build ios --release --no-codesign`, then `fastlane build` archives again with `build_app`, which runs Flutter's build phase a second time. Replace the first with `flutter build ios --config-only --release --build-name --build-number`, which writes `Generated.xcconfig` and pods with no compile. The speech-parts check in the Fastfile still reads the exported `.ipa`, so a missing part still fails. If the archive then fails on a branch run, keep the full build and record why in the Decision log.

### Device check: overlap the slow parts

- **Boot early.** Split `iphone-open.sh` into `iphone-boot.sh` (pick the iPhone, `simctl boot` in the background, write `DEVICE_UDID`) run before *Build for the simulator*, and `iphone-open.sh` (wait with `bootstatus`, install, video, launch) after it.
- **One Maestro run for the tour.** `maestro test --format junit --output "$OUT/maestro/tour.xml" flows/timeline.yaml flows/new-note.yaml flows/settings.yaml` keeps one driver for the three flows. `tour.json` comes from the JUnit file, one entry per flow, in the same shape, so `finish.sh` and the release gate read it as today. Screenshots keep their names. If Maestro 2.12.1 runs the files in another order or stops after the first failure, apply falls back to one run per flow with `--no-reinstall-driver` and records it.
- **Swift tests on a second Mac.** A new job `swift-tests` (`runs-on: macos-latest`, same commit check) runs `xcodebuild test -only-testing:RunnerTests` on a fresh simulator, in parallel with `iphone`. It uploads `swift-tests.log` as `device-check-swift`. `report` needs both and adds one line: Swift tests passed or failed. The release gate fails when `swift-tests` fails. Alternative: `build-for-testing` once and install that app; rejected because the tour must run the Flutter build the person ships, and a shared `DerivedData` makes the two steps depend on each other.
- **Concurrency.** On job `iphone` and `swift-tests`: `group: device-check-${{ inputs.tour_only && format('release-{0}', inputs.sha) || github.head_ref || github.ref_name }}`, `cancel-in-progress: ${{ !inputs.tour_only }}`. `scripts/device-check.mjs` prints `result=cancelled` when its run is cancelled, so `/verify` says a newer check replaced it.

### Claude: room to finish, and a reason when it does not

- `--max-turns 80`; the step keeps `timeout-minutes: 20`.
- `allowedTools` adds `Bash(mkdir -p out/claude:*)`, `Bash(ls:*)`, `Bash(sleep:*)`, `Glob`, `Grep`, and `Bash(bash mobile/device-check/flow.sh:*)`. `Bash(maestro:*)` goes: Claude runs flows only through `flow.sh`. `Edit` and `Write` stay inside `./out/claude/**`. None of these reads a secret, and `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` stays.
- `flow.sh <file>`: runs `maestro test` with a 90 s limit (a background `kill` timer: macOS has no `timeout`), and on a hang kills Maestro and its driver and tries once more. It prints `result=passed|failed|hung`.
- `brief.md`: after reading `tour.json`, write `out/claude/report.md` with every scenario as *not yet checked* and `verdict.txt` as `could-not-check`; update both after each scenario. Stop after 60 tool calls. `iphone.md` names `flow.sh` in place of `maestro test`.
- **Step log.** After the Claude step (`if: always()`), a step reads the action's `execution_file` output and writes `out/claude/steps.md` with `node`: one line per tool call (tool name, its command or path, cut to 200 characters), *refused* on each denied call, and the result's `subtype`, `num_turns` and `duration_ms`. Images and tool output are left out. It writes `out/claude/end.txt` with the reason: `error_max_turns` → *used all 80 turns*, a cancelled step → *ran out of time*, refused calls → *N commands were refused*, else *stopped with no verdict*.
- **finish.sh.** Claude's verdict missing while Claude ran (no `claude-skipped.txt`): verdict `no-verdict`, reason from `end.txt`, and exit 1. The report keeps Claude's partial `report.md`. A verdict of `could-not-check` that Claude wrote stays green. `/verify`'s rule and `scripts/device-check.mjs` treat `no-verdict` as *not verified*.

## Risks / Trade-offs

- The step log is public. It holds commands, paths and screen text from test data; the key is scrubbed from every command's environment and never in a tool input. A screen that shows a person's data does not exist on the simulator.
- A second Mac per check doubles Mac minutes. The repository is public, so GitHub's Macs cost nothing.
- arm64-only branch files will not install on an x86 Android emulator. Main's pre-release still has every ABI.
- Red on no verdict can fail a check for a device-tool fault the change did not cause. The reason line names it, and the step log shows it.
- A cancelled check after `/verify` starts it: `device-check.mjs` reports it as cancelled, and `/verify` starts the newest one.
