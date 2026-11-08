# Proposal: Faster checks for each save, and an iPhone check that always gives an answer

**Status:** ready-to-ship
**Branch:** speed-up-ci-claude-check
**Open questions:** none

## Why

A save that changes the phone app waits about 10 minutes for its checks, and the iPhone check takes 30 to 40 minutes. The iPhone check also often gives no answer: in 4 of its last 6 runs Claude stopped before it wrote a verdict, but the check still showed green, so a person could think the change was checked when it was not.

## What Changes

- **The phone app's checks finish sooner, with every test kept.** Both apps start to build at the same time as the tests, not after them. The Android build keeps its slow speech part between runs, and a branch builds Android only for the phones in use today. The iPhone build compiles the app once, not twice. A test that fails still stops every beta and release.
  ```text
  Before (about 10 min)
  tests   ##
  builds    ##########
  After (about 5 to 6 min)
  tests   ##
  builds  ######
  ```
- **The iPhone check takes about half the time.** The iPhone starts up while the app builds. The fixed tour runs its three steps in one go. The iPhone's own code tests run on a second Mac at the same time, not at the end. A new check on the same branch stops the older one, so checks no longer pile up.
  ```text
  Before (30-40 min)
  build|start iPhone|tour   |Claude  |code tests
  After (about 15-20 min)
  build+start|tour|Claude
  code tests (second Mac)
  ```
- **Claude has the room to finish, and writes as it goes.** Claude gets more turns and a few safe everyday commands, such as making a folder and listing files. It writes its report after each scenario, so a stop keeps what it found. A tap step that hangs stops after 2 minutes and tries once more, so one stuck tap does not end the whole check.
- **No verdict shows red, with the reason.** When Claude stops with no verdict, the check fails and says why: out of time, out of turns, or commands refused. A verdict of *could not check* that Claude gives on purpose, with its reason, stays green.
  ```text
  iPhone check: no verdict          [red]
  Claude used all 80 turns before it
  wrote a verdict. 3 of 7 scenarios
  checked. See claude/steps.md.
  ```
- **The run keeps a log of what Claude tried.** Each command Claude ran, and each one that was refused, goes in the run's files. The repository is public, so anyone signed in to GitHub can read the log. It holds only test data and screen text, never the key.

Non-goals: building the apps less often; an Android device check; changing which checks must pass before a change is published; changing the tour's steps for the new screens (the change that moves a screen updates its tour step).

## What the build needs

- **Nothing.** The work runs on GitHub's free Macs and the existing Claude token.

## Decision log

- **2026-11-08** — Asked how each save of a phone change should build the two apps → chose build them at the same time as the tests and keep the slow Android part between runs, with every save still building both apps.
- **2026-11-08** — Asked what a check with no verdict should show → chose red, with the reason.
- **2026-11-08** — Asked whether to keep a log of what Claude tried in the run's public files → chose keep the log.
- **2026-11-08** — Assumed: a beta or release still waits for the tests before it builds, because only a branch build can start early without risk; a branch publishes nothing.
- **2026-11-08** — Assumed: a branch builds the Android file for 64-bit ARM phones only, because every phone the file is tried on is one, and it cuts the speech part's build to a third; main and releases keep every kind.
- **2026-11-08** — Assumed: a newer iPhone check on the same branch cancels the older one, because 5 checks piled up on one branch on 2026-11-08 and only the newest commit matters; a release's tour gate is never cancelled.
- **2026-11-08** — Assumed: Claude's turn limit goes from 40 to 80 and its time limit stays 20 minutes, because a scenario takes 4 tool calls (write a flow, run it, take a picture, look at it) and 40 turns ran out in 3 scenarios.
- **2026-11-08** — Assumed: the run's failures on 2026-11-06 and 2026-11-08 where a tour step failed were tour steps out of date with a changed screen, not a fault in the check, so this plan does not change the tour's steps; a faster check shows them sooner.
- **2026-11-08** — Assumed: the tour runs in one Maestro run with no fallback, because Maestro 2.12.1's source (`TestCommand`, `WorkspaceExecutionPlanner`, `TestSuiteInteractor`) runs the given files in the order given, goes on after a failed flow, and writes one JUnit test case per flow.
- **2026-11-08** — Assumed: `iphone` and `swift-tests` each get their own concurrency group (`device-check-iphone-…`, `device-check-swift-…`), because one shared group would make the two jobs of one run stop each other.
- **2026-11-08** — Assumed: a Claude that stops before it ends on its own (out of turns, out of time, an error) gives `no-verdict` even when its `verdict.txt` holds the brief's first `could-not-check`, because Claude writes that word before it checks anything. `steps.mjs` writes `end.txt` whenever Claude gave no final verdict.
- **2026-11-08** — Assumed: a cancelled check posts no comment on the pull request, because the newer check posts its own.
- **2026-11-08** — Assumed: the Android cache also keeps the NDK, because the speech objects depend on the NDK's headers, and a new download with new file times could make each object build again. The speech package's CMake objects go in its own `android/.cxx` in the pub cache (AGP's default; the package sets no other folder), read from its `build.gradle`, not measured on a run: task 5.2 shows it in the second run's Build time.
- **2026-11-08** — Assumed: `scripts/device-check.mjs` downloads `device-check-swift` too and reports `broken` when the Swift tests fail, as when they ran on one Mac. `mobile/ios/fastlane/Fastfile` needs no change: `build_app` reads the version from the files that `--config-only` writes.
- **2026-11-08** — Assumed: when the action wrote no execution file, because Claude ran out of time, `steps.mjs` reads the newest `~/.claude/projects/*/*.jsonl` session file instead, because Claude Code writes it as it goes and the step log would otherwise be empty when it matters most. It holds the same `assistant` and `user` messages, and the log still keeps only each tool's name and target.
- **2026-11-08** — Check: `.github/workflows/mobile-ci.yml` a branch's builds no longer wait for the Flutter tests, because a branch publishes nothing and a failed test still makes the run red; main and a release still build only after the tests pass.
- **2026-11-08** — Check: `.github/workflows/mobile-android.yml` a branch's Android file is built for 64-bit ARM only, because every phone the file is tried on is one; main and a release still build every kind.
- **2026-11-08** — Check: `.github/workflows/mobile-ios.yml` the separate full `flutter build ios` before the archive becomes `--config-only`, because fastlane's archive compiles the same app again and the speech-parts check still reads the exported `.ipa`.
- **2026-11-08** — Check: `.github/workflows/mobile-device-check.yml` Claude gets 80 turns and `ls`, `sleep`, `mkdir -p out/claude`, Glob, Grep and `flow.sh` in place of `maestro`, and a newer check of a branch cancels the older one, because Claude ran out of turns and was refused harmless commands, and only the newest commit matters; no command reads a secret, a release's tour is never cancelled, and the Swift tests still gate a release from their own job.
- **2026-11-08** — Built inside /ship; the second look found 7 problems (a cut-off `flow.sh` retry, an empty step log after a time-out, unfinished Swift tests counted as failed, and four smaller ones), all fixed; saved for the live checks (tasks 5.2 and 5.3).
- **2026-11-08** — Live checks on the saved branch (PR #68): Mobile CI took 7 min (was about 10): tests 1.5 min, both builds started with them; the Android build took 4 min 52 s with no cache and 3 min 6 s with it (was 6 min 35 s), and the iPhone build with its signed archive about 6 min 50 s (was about 8.5 min), now the slowest part. Two iPhone checks in a row: the first was cancelled, both jobs; the second said *works* in 25.7 min (was 30 to 40), with `claude/steps.md`, the Swift tests on the second Mac, and `flow.sh`'s retry getting past a stuck app launch.
- **2026-11-08** — Assumed after that check: the iPhone starts after the 2 GB Flutter download, not before it, because the two at once took the download from under 1 min to 4 min 9 s and the build from 3-4 min to 7 min; `flow.sh` waits 120 s, not 90 s, because a finished 10-step flow ran past 90 s; Claude may run `mkdir -p` anywhere and `out/claude/flows/` is made for it, because `mkdir -p out/claude/flows` was refused by the narrower rule.
- **2026-11-08** — Archived inside /ship and saved for the gate; the specs for app builds and the device check now hold this change.
- **2026-11-08** — Took main with #66 (a Settings gear on Home): its `settings.yaml` stays as #66 wrote it, and the one-run tour runs it as its fourth flow.

## Capabilities

### New Capabilities

### Modified Capabilities
- `relay-app-builds`: a branch build no longer waits for the tests; a beta or release still does.
- `relay-app-device-check`: a newer check on a branch cancels the older one; Claude's missing verdict fails the check with a reason; the run keeps Claude's step log.

## Impact

- `.github/workflows/mobile-ci.yml`: branch build jobs that need only `plan`; beta and release jobs that still need `flutter`.
- `.github/workflows/mobile-android.yml`: `--target-platform android-arm64` for `mode == branch`; cache the speech package's CMake output (`.cxx`) and Gradle build cache.
- `.github/workflows/mobile-ios.yml` and `mobile/ios/fastlane/Fastfile`: `flutter build ios --config-only` before the fastlane archive, in place of a full `flutter build ios`.
- `.github/workflows/mobile-device-check.yml`: job concurrency, early simulator boot, a parallel `swift-tests` job, `--max-turns 80`, wider `allowedTools`, the Claude execution file into `out/claude/steps.md`.
- `mobile/device-check/`: `iphone-open.sh` split into boot and install, `tour.sh` one Maestro run, new `flow.sh` (120 s limit, one retry), `finish.sh` no-verdict reason and exit, `brief.md` and `iphone.md` write-as-you-go.
- `wiki/development/device-check.md`, `mobile/README.md#builds-on-github`, `.agents/rules/mobile.md` if it names the old steps.
