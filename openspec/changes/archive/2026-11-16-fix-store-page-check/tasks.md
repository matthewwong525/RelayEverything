# Tasks

## 1. The fix

- [x] 1.1 In `mobile/ios/fastlane/Fastfile`, run `check_listing`'s file reads (`File.directory?` on `LISTING_METADATA`, `Deliver::Loader.load_app_screenshots` on `LISTING_SCREENSHOTS`) inside `Dir.chdir("..") do ... end`
- [x] 1.2 In `scripts/app-release.test.mjs`, assert that `check_listing` changes to `..` before its first `LISTING_` read

## 2. Checks

- [x] 2.1 `node --test scripts/app-release.test.mjs scripts/app-store-listing.test.mjs` and `node scripts/public-check.mjs`

## After the publish

Run the release check from `main` (`gh workflow run mobile-ci.yml --ref main -f release_check=true`) and confirm the step *App Store page* prints `Ready: the App Store page in en-CA has 11 screenshots. Nothing was sent.`
