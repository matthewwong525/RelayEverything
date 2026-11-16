# Fix the release check's App Store page step

**Status:** ready-to-ship
**Branch:** fix-store-page-check
**Open questions:** none

## Why

The release check from `main` stopped at the App Store page step. It said the page files had no `en-CA` folder, but the folder is there. The check looked for the files in the wrong folder. So a `v1.0.0` tag would stop at the same step, and the app can't go to App Store review until this is fixed. The page files themselves are correct.

## What Changes

- **The App Store page step finds the page files.** The release check reads the store page's words and screenshots from the right folder. Then it shows the result it was made to show: the page is ready, and nothing was sent.
  ```text
  Release check from main
  ─────────────────────────────────────────────
  Before:  App Store page   ✗  "has no en-CA folder"
  After:   App Store page   ✓  "Ready: the App Store page in
                                en-CA has 11 screenshots.
                                Nothing was sent."
  ```
- **A test keeps it fixed.** The repository's checks fail if the page step looks in the wrong folder again.

**Not in this change:** the `v1.0.0` tag. After this is live, I run the release check again. When it passes, you push the tag, or ask me to.

## What the build needs

- **Apple's key**: Ready. The release check already uses it.
- **The Mac signing secrets**: Ready. They were set on 2026-11-16, and the Mac part of the release check passed.

## Capabilities

### New Capabilities

### Modified Capabilities
- `app-store-listing`: adds the promise that the release check reads the same page files the release sends, and fails only for a real fault.

## Impact

- `mobile/ios/fastlane/Fastfile`: `check_listing` reads the page files from `mobile/ios/`.
- `scripts/app-release.test.mjs`: one more assertion.

## Decision log

- **2026-11-16** — Assumed: `check_listing` reads its files inside `Dir.chdir("..")`, not with new absolute path constants, because fastlane runs lane code from `fastlane/` and its own actions from the folder above. So the same relative paths keep working for `deliver`, which already reads them from there.
- **2026-11-16** — Assumed: the spec adds one promise to `app-store-listing`, that the release check reads the files the release sends, because this bug broke that promise without breaking a written one.
- **2026-11-16** — Asked whether to publish this fix and release v1.0.0 now, given the Mac app opens to a black window until plan mac-download-fix-and-installer ships → chose to publish this fix now and wait with v1.0.0 until the Mac fix is live.
- **2026-11-16** — Archived for publishing, with every task done.
