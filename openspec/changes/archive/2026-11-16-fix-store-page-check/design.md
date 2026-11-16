# Design

## Context

Run 43782897767 (release check on `main`, 2026-11-16) failed in the step *App Store page*: `[!] App Store Connect's primary language is en-CA, but ./fastlane/metadata has no en-CA folder.` fastlane runs the code of a lane from inside `fastlane/`, but it runs each action, such as `deliver`, from the folder above (`Dir.chdir("..")` in fastlane's runner). `LISTING_METADATA` and `LISTING_SCREENSHOTS` are `./fastlane/...` paths, so they are right for `deliver` and wrong for the plain Ruby reads in `check_listing`.

## Decisions

### Read the page files from the folder above, as actions do

Wrap the two file reads in `check_listing` (`File.directory?` and `Deliver::Loader.load_app_screenshots`) in `Dir.chdir("..") do ... end`. The API reads stay outside. **Alternative:** make the constants absolute with `File.expand_path(..., __dir__)`. Rejected: `__dir__` in a Fastfile depends on how fastlane evaluates the file, and `deliver` already takes the relative paths.

### Test

`scripts/app-release.test.mjs` already reads the `listing` lane. Add: `check_listing`'s body has `Dir.chdir("..")` before its first `LISTING_` read.

## Risks / Trade-offs

- [The check passes the folder test but fails at the screenshots] → the same `Dir.chdir` covers both reads; the release check shows it.
