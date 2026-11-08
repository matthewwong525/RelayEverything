# Design: release the phone app with a tag

## Context

See [proposal.md](proposal.md), Why. Today:

- `mobile-ci.yml` runs on a push to any branch, and its `ios` job runs for every non-PR event, so each branch push uploads to TestFlight. Build numbers are `github.run_number`, shared by all branches: run 98 (branch `iphone-build-signing`) is above main's run 96, so TestFlight's newest build is a branch build.
- `mobile-android.yml` makes a release marked `--latest` on each main push, titled *Relay for Android* (a bare *Relay*), and signs with a debug key because `RELAY_ANDROID_*` secrets are not set.
- `mobile-ios.yml` + the `beta` lane in `mobile/ios/fastlane/Fastfile` build, sign, check the speech parts and upload to TestFlight. PR #54 (`ios-signing-reuse`) rewrites the signing part of both files; this change builds on main after #54 lands.
- `mobile-device-check.yml` already has the fixed Maestro tour (`mobile/device-check/iphone-open.sh`, `tour.sh`) and fails hard only when the first flow fails.
- `Info.plist` already sets `ITSAppUsesNonExemptEncryption` to false, so a submission needs no export answer.

## Goals / Non-Goals

**Goals:** one build-number counter for every build; uploads only from main, newest-only; a tag run that gates every outward step on the full test; release notes and PR marks made by code, not by an agent; rerunnable release steps.

**Non-Goals:** Google Play; editing the App Store listing (description, screenshots, privacy answers) from the repository; phased release; a release of the server or the website (they publish on each merge).

## Decisions

### One workflow for branch, main and tag

`mobile-ci.yml` gains `push.tags: ['v*']`. GitHub does not apply `paths` filters to a tag push, so each tag runs. Keeping the tag in the same workflow keeps `github.run_number` one counter, so a release's build number is always above every beta and branch build. A separate `release.yml` would start its own counter at 1, below TestFlight's 98: Apple refuses it.

A new first job, `plan`, runs `node scripts/app-release.mjs version` with full history and tags (`fetch-depth: 0`). It prints `mode` (`branch`, `beta`, `release`, or `release-check`), `version`, `build` and `previous_tag` to `$GITHUB_OUTPUT`. In `release` mode it fails at once when the tag is not `vX.Y.Z`, when the tagged commit is not an ancestor of `origin/main`, or when the version is not above the newest earlier `v*` tag (semver order, not text order). The `flutter`, `android`, `ios` jobs take these outputs as inputs and pass `--build-name` and `--build-number` to `flutter build`, so `pubspec.yaml` needs no version edit.

Beta version: the newest `v*` tag with patch + 1; with no `v*` tag, the `pubspec.yaml` version (1.0.0 today). The old `mobile-v1.0.0+N` tags are not release tags: the tag pattern is `^v\d+\.\d+\.\d+$` exactly.

Alternative: `fastlane latest_testflight_build_number + 1`. Rejected: it covers iOS only, needs the Apple key on branches, and races between two runs.

### Newest-only uploads on main

Two layers:

1. **Concurrency** stays `mobile-ci-push-main` with no cancel for `main`, so main runs go in order and GitHub keeps only the newest pending run. A tag run uses its own group, `mobile-release-<tag>`, never cancelled.
2. **A guard before each upload** (the TestFlight upload and the Android pre-release): `git fetch origin main`, then `git diff --quiet "$GITHUB_SHA" origin/main -- mobile/`. A difference means a newer commit on main changed the app, and that commit's own run uploads: this run skips with a notice. A newer commit that changes only the server does not count, so its absence never leaves the app without a beta.

### Branches build, never upload

The Fastfile splits into a private `build_signed` (signing from #54, archive, `check_speech_parts`) and two lanes: `build` (branch: stops after the check) and `beta` (main and release: `build_signed` + `upload_to_testflight`). A release build goes to App Store Connect with the same upload; App Store submission picks it by build number. `mobile-ios.yml` takes an `upload` input; `mobile-ci.yml` sets it only for `beta`, `release` and `release-check` modes.

### Submission runs on Linux, after the gate

A new `release` job in `mobile-ci.yml` `needs: [plan, android, ios, tour]` and runs only in `release` and `release-check` modes, on `ubuntu-latest` (fastlane's App Store Connect calls need no Mac, and the wait for Apple's processing should not hold a Mac). Its steps:

1. `node scripts/app-release.mjs notes` → `notes.md` (GitHub) and `whats-new.txt` (App Store, plain text, at most 4,000 characters, cut at a line with *…and more* plus the release link).
2. `bundle exec fastlane submit` in `mobile/ios`: `deliver` with `app_version`, `build_number`, `skip_binary_upload`, `skip_screenshots`, an empty `metadata_path` and only `release_notes` given, so the listing does not change; `submit_for_review: true`, `automatic_release: true`, `run_precheck_before_submit: false`, `submission_information: { add_id_info_uses_idfa: false }`, `force: true`. It waits for the build to finish processing. Before it calls `deliver`, the lane reads the version's state through Spaceship and skips when it is already `WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_DEVELOPER_RELEASE` or `READY_FOR_SALE`. In `release-check` mode the lane checks that the build is processed and the version can be made, then stops before `deliver`.
3. `gh release create "$TAG" relay-everything-<version>.apk --title "Relay Everything <version>" --notes-file notes.md --latest --verify-tag`; on a rerun, `gh release upload --clobber` and `gh release edit`. In `release-check` mode: `--draft`, deleted at the end of the job.
4. `node scripts/app-release.mjs mark`: `gh label create released --force` once, then for each PR `gh pr edit --add-label released` and a comment that holds the marker `<!-- relay-everything-release v1.1.0 -->`, skipped when a comment with that marker exists. Not run in `release-check` mode.

The job gets `contents: write`, `pull-requests: write`, `issues: write`; the other jobs keep `contents: read` except `android` (pre-release).

Alternative: submit inside the Mac `ios` job. Rejected: the submit must wait for the tour, and a Mac minute costs ten Linux minutes on a private copy of the repository.

### The tour as a gate

`mobile-device-check.yml` gains `workflow_call` with inputs `sha` and `tour_only` (boolean). With `tour_only`, the job's `if` passes for the call, the Claude steps skip, and a final step fails unless every entry in `tour.json` has `passed: true`. The run still uploads its pictures as an artifact, so a failed release shows the screen it stopped on. `mobile-ci.yml` calls it as job `tour` in `release` and `release-check` modes.

### Release notes and PR list by code

`scripts/app-release.mjs`, on `scripts/lib-cli.mjs` like the other scripts, holds pure, tested functions and thin `git` / `gh` calls:

- `parseTag`, `compareVersions`, `nextBeta`, `planRun({ ref, sha, isOnMain, tags, pubspecVersion })` → the `plan` outputs.
- `commitsForApp(prev, tag)`: `git log --format=%H%x1f%s prev..tag -- mobile/` (no `prev`: the whole history).
- `pullNumber(subject)`: the squash-merge suffix `(#53)`; no suffix keeps the commit's first line.
- `groupNotes(items)`: label `enhancement` → *New*, `bug` → *Fixes*, others → *Changes*; GitHub Markdown with links and `**Full list**: <compare link>`; App Store text with no Markdown.

`gh` reads each PR's title and labels; the test injects a fake. The script is added to the `node --test` list in `app/package.json`'s `test`. Not `gh release create --generate-notes`: it cannot leave out the server and website PRs.

### The Android upload key

The build makes the key once with `keytool` (RSA 2048, validity 10,000 days, alias `upload`) in a temporary folder outside the repository, writes the four `RELAY_ANDROID_*` values to the primary worktree's `.env`, sets them with `gh secret set`, and deletes the folder. No value is printed. `mobile-android.yml` fails in `release` and `release-check` modes when the key is missing; branch builds keep the debug-key warning.

### Names

Release titles: *Relay Everything <version>* for a tag, *Relay Everything for Android <version>, build <n>* for a pre-release. The beta tag stays `mobile-v<version>+<build>` so old links still work.

## Risks / Trade-offs

- [Apple allows one version in review at a time] → a new tag while the last is still in review fails at `deliver` with Apple's message; rerun the `release` job once the earlier review ends. The design says so in `mobile/README.md`.
- [The first submission needs the listing and a final privacy policy] → the `release-check` run proves the pipeline without a submission; the person fills the listing before the first real tag (proposal: What you do yourself).
- [Phones with the debug-signed file] → they must remove it once; the website install page and the first release notes say so.
- [Every branch push now signs an iPhone build on a Mac] → the repository is public, so GitHub's Macs cost nothing; the build already ran on each branch push before.
- [Apple's processing can take over 30 minutes] → the `release` job has a 90-minute timeout; a rerun skips steps already done.
- [A tag on a commit whose main run is still going] → the tag run builds on its own and its build number is higher, so the order holds.

## Migration Plan

1. Land after #54. The first main run after this change uploads betas as before, but as a pre-release; the latest GitHub release stays `mobile-v1.0.0+96` until the first tag.
2. Run the `release-check` from `main` once (`gh workflow run mobile-ci.yml -f release_check=true`).
3. The person fills in the App Store listing and the final privacy policy, then tags `v1.0.0`.

Rollback: revert the change. Tags and releases already made stay; nothing else holds state.
