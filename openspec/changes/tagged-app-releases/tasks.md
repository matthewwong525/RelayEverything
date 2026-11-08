## 1. Start point

- [x] 1.1 Wait until PR #54 (`ios-signing-reuse`) is on `main`, then bring `main` into this branch; `git log origin/main --oneline -- mobile/ios/fastlane/Fastfile` shows #54's commit

## 2. Release script

- [x] 2.1 `scripts/app-release.mjs` on `scripts/lib-cli.mjs`: `version` (prints `mode`, `version`, `build`, `previous_tag` for `$GITHUB_OUTPUT`; refuses a bad, off-main or not-higher tag), `notes` (writes `notes.md` and `whats-new.txt` from commits that changed `mobile/` since the previous `v*` tag), `mark` (label *released*, one comment per PR with the version marker); verified by 2.2
- [x] 2.2 `scripts/app-release.test.mjs`: semver order (`v1.10.0` > `v1.9.0`), `mobile-v1.0.0+96` is not a release tag, beta version after `v1.1.0` is `1.1.1` and is the `pubspec.yaml` version with no tag, off-main and lower tags refused, squash `(#53)` read and a no-PR commit kept, server-only commits left out, grouping by label, What's New under 4,000 characters, `mark` skips a PR that already has the marker comment (fake `gh`); add it to the `node --test` list in `app/package.json`; `node --test scripts/app-release.test.mjs` passes

## 3. Workflows and fastlane

- [x] 3.1 `mobile-ci.yml`: `push.tags: ['v*']`, a `workflow_dispatch` input `release_check`, the `plan` job (full history and tags), mode inputs to `android` and `ios`, a `mobile-release-<tag>` concurrency group for tags; `actionlint` passes on the file
- [x] 3.2 `mobile-android.yml`: `mode`, `version`, `build` inputs; branch → run artifact; beta → pre-release `mobile-v<version>+<build>` titled *Relay Everything for Android …*, not latest, behind the newest-on-main guard; release and release-check → artifact for the `release` job, and fail with the secret names when the upload key is missing
- [x] 3.3 `Fastfile`: `build_signed` shared by a `build` lane (no upload) and the `beta` lane; a `submit` lane (`deliver` with only release notes, automatic release, skip when the version is already in review or live, `--check` stops before `deliver`); `mobile-ios.yml` takes `upload`, `version`, `build`, and runs the newest-on-main guard before `beta` on main
- [x] 3.4 `mobile-device-check.yml`: `workflow_call` with `sha` and `tour_only`; with `tour_only` the Claude steps skip and the job fails unless every flow in `tour.json` passed; pictures stay as an artifact
- [x] 3.5 `mobile-ci.yml` jobs `tour` and `release` (`needs` all of `plan`, `android`, `ios`, `tour`; release and release-check modes only; `timeout-minutes: 90`): notes, `fastlane submit`, `gh release create … --latest --verify-tag` (or edit and upload on a rerun; a draft deleted at the end in release-check), then `mark` (not in release-check)

## 4. Android upload key

- [x] 4.1 Make the upload key with `keytool` in a temporary folder outside the repository; write the four `RELAY_ANDROID_*` values to the primary worktree's `.env` and `gh secret set` them; delete the folder; print no value. `gh secret list` shows all four

## 5. Docs and website

- [x] 5.1 `mobile/README.md` *Builds on GitHub*: betas from main only, newest-only; how to release with a tag; the release-check run; one version in review at a time; the App Store listing and privacy policy before the first release
- [x] 5.2 `wiki/open-source.md` *Phone builds* and the `AGENTS.md` phone builds line: TestFlight and pre-releases from `main`, a `v<x.y.z>` tag releases to the App Store and as the latest GitHub release
- [x] 5.3 `site/src/content/docs/start/install.md`: Android takes the newest release; a phone with an older file removes it once; betas are under pre-releases; iPhone through TestFlight until the App Store release; remove the stale *not in TestFlight yet* note. `index.mdx` hero links stay right; `node --test scripts/product-name.test.mjs` passes

## 6. Checks

- [x] 6.1 Run `npm test` in `app/` and `node scripts/public-check.mjs`
- [ ] 6.2 `/save`; on the branch's run: the iPhone app builds and nothing reaches TestFlight, and no GitHub release is made
After publish (not tasks, because a task can't wait for its own publish; `/ship` runs them right after the merge):

- The first main run uploads one TestFlight build and one pre-release, and the latest GitHub release does not change.
- `gh workflow run mobile-ci.yml --ref main -f release_check=true`: the tour passes, the build reaches App Store Connect, `submit --check` reports ready, a draft release with the notes and the signed `.apk` is made and deleted, and no PR is marked.
