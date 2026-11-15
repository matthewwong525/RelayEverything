# Tasks

## 1. The page files

- [x] 1.1 Add `mobile/ios/fastlane/metadata/en-CA/`: `name.txt` (*Relay Everything*), `subtitle.txt`, `description.txt`, `keywords.txt`, `promotional_text.txt`, `support_url.txt`, `marketing_url.txt`, `privacy_url.txt`; and `metadata/copyright.txt`, `primary_category.txt` (`PRODUCTIVITY`), `secondary_category.txt` (`UTILITIES`), `review_information/notes.txt`, by design.md *Keep the page in fastlane's deliver layout*. Words follow `wiki/voice.md`; no email, phone or bare *Relay*
- [x] 1.2 Add `mobile/ios/fastlane/rating.json` with the age rating answers in design.md
- [x] 1.3 Add `mobile/ios/fastlane/app_privacy_details.json` in fastlane's format with the table in design.md
- [x] 1.4 Write `scripts/app-store-listing.test.mjs` (limits, required files, https links, categories, rating keys, screenshot PNG sizes per device, no email or phone); add the metadata files to `scripts/product-name.test.mjs`

## 2. The listing lane and the release

- [x] 2.1 Add a `listing` lane to `mobile/ios/fastlane/Fastfile` (`version:`, `verify_only:`) that runs `deliver` with the metadata, screenshots and rating paths, `overwrite_screenshots: true`, `skip_binary_upload: true`, `submit_for_review: false`, `force: true`; `submit` stays unchanged
- [x] 2.2 In `.github/workflows/mobile-ci.yml`'s release job, run `fastlane listing` before `fastlane submit`, and `fastlane listing verify_only:true` in a release check; extend `scripts/app-release.test.mjs` to check both

## 3. Screenshots

- [x] 3.1 Add Maestro flows in `mobile/device-check/store/` that make the sample notes and take Home, a note, search and Settings
- [x] 3.2 Add `.github/workflows/mobile-store-screenshots.yml` (`workflow_dispatch`, `main` only): jobs for the Pro Max iPhone, the 13-inch iPad and the Apple Watch, reusing the device check's boot, build and open scripts; one artifact `store-screenshots` in deliver's folder layout
- [ ] 3.3 `/save`, then run the screenshot workflow on the branch's commit (a branch run is allowed to make pictures only), download the artifact into `mobile/ios/fastlane/screenshots/en-CA/`, look at each picture, and confirm the test in 1.4 takes their sizes

## 4. One-time App Store Connect settings (outward, confirm each)

- [ ] 4.1 (outward) Through the API: price free in all territories, and the reviewer contact from the memory store (never the repo)
- [ ] 4.2 (outward) In the browser signed in as Matthew: set the App Privacy answers to match `app_privacy_details.json`, and publish them

## 5. Docs

- [x] 5.1 `mobile/README.md`: replace *Left before the first App Store version* with where each part of the page lives, how to take new screenshots, how to change the privacy answers, and what the release now sends; update the *Release the app* step 1
- [x] 5.2 `wiki/open-source.md` and AGENTS.md *Phone builds*: a release also sends the store page

## 6. Checks

- [ ] 6.1 `node --test scripts/app-store-listing.test.mjs scripts/app-release.test.mjs`, `node scripts/product-name.test.mjs`, `node scripts/public-check.mjs`
- [ ] 6.2 `/save`, then after the publish run the release check from `main` (`gh workflow run mobile-ci.yml --ref main -f release_check=true`) and confirm `deliver` verifies the page with no error

## After the publish

`/ship` reports the release check's result and tells Matthew the app is ready for `v1.0.0`. It runs `node scripts/publish-relay-site.mjs` and `node scripts/publish-relay-server.mjs` only if `site/` or `app/` changed.
