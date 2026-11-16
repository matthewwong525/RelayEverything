# Design

## Context

See proposal.md, *Why*. A read of App Store Connect on 2026-11-15 (app 6831389959) showed: app name `RelayEverything`, primary locale `en-CA`, one editable version `1.0` in `PREPARE_FOR_SUBMISSION`, and every listing field empty (description, keywords, support URL, subtitle, privacy URL, category, age rating declaration, review detail, copyright). The `submit` lane in `mobile/ios/fastlane/Fastfile` runs `deliver` with an empty `metadata_path` and `skip_screenshots: true`, so it never touches the page. The app is universal (`TARGETED_DEVICE_FAMILY = "1,2"`) and ships a watch app, so Apple needs iPhone, iPad and Apple Watch screenshots. `ITSAppUsesNonExemptEncryption` is already `false`. The app has *Delete my account* (guideline 5.1.1(v)) and offers Sign in with Apple on its sign-in page (guideline 4.8).

## Goals / Non-Goals

**Goals:** a submittable page from the repo; one command path (`deliver`) for words, screenshots, categories and age rating; the release sends it.

**Non-Goals:** localizations other than `en-CA`; App Preview videos; In-App Events; an organization developer account; captions on screenshots.

## Decisions

### Keep the page in fastlane's `deliver` layout

`mobile/ios/fastlane/metadata/en-CA/{name,subtitle,description,keywords,promotional_text,support_url,marketing_url,privacy_url}.txt`, plus `metadata/{copyright,primary_category,secondary_category}.txt` and `metadata/review_information/notes.txt`. `deliver` reads this layout with the API key we already use. **Alternative:** our own JSON plus direct API calls. Rejected: more code to own, and `deliver` already handles screenshot sets, ordering and replacement.

Values:
- `name`: `Relay Everything` (≤30). `subtitle`: a ≤30-character line, such as *Your notes, health and places* (29) (final wording at build; the check enforces length).
- `primary_category`: `PRODUCTIVITY`; `secondary_category`: `UTILITIES`.
- `support_url`: `https://github.com/matthewwong525/RelayEverything/issues`, because the site guard refuses email addresses and GitHub issues is the published way to reach us. `marketing_url`: `https://relayeverything.com/`. `privacy_url`: `https://relayeverything.com/privacy/`.
- `copyright`: `2026 Relay Everything`, as the `/terms` page names the sole proprietorship *Relay Everything*.
- Reviewer note: the app works fully with no account; sign-in is optional and offers Sign in with Apple; health, location, calendar and photos ask permission only when the person turns on each one; voice notes are written on the phone. No demo account: sign-in uses Sign in with Apple or an email code, which a reviewer can do with their own Apple ID.

### Age rating as `rating.json`

`deliver`'s `app_rating_config_path` takes the current age rating questionnaire keys. All `NONE`/`false` except `healthOrWellnessTopics: true` (the app shows the person's own health numbers), and `unrestrictedWebAccess: false` (links open in the system browser, not an in-app browser). Expected result: 4+ or 9+, whichever Apple computes; the check does not assert the result.

### A `listing` lane, run by the release before `submit`

```text
lane :listing (verify_only: bool)
  deliver(api_key, app_version: <tag>, metadata_path, screenshots_path,
          app_rating_config_path, overwrite_screenshots: true,
          skip_binary_upload: true, submit_for_review: false,
          run_precheck_before_submit: false, verify_only:, force: true)
```

In `mobile-ci.yml`'s release job: `fastlane listing` before `fastlane submit`; in a release check: `fastlane listing verify_only:true`. `submit` keeps its empty metadata folder, so it sends only *What's New* and does not undo the listing. `app_version` from the tag moves the editable version `1.0` to `1.0.0`. **Alternative:** a separate workflow to push the page on each change to `metadata/`. Rejected: a page change between releases would show on the live page before the app it describes; with the release, page and app go live together.

### Screenshots from a Maestro run on a GitHub Mac

New `.github/workflows/mobile-store-screenshots.yml` (`workflow_dispatch`, `main` only), reusing the device check's boot, build and open scripts. Devices: the newest *Pro Max* iPhone (6.9", 1320×2868 or 1290×2796), *iPad Pro 13-inch* (2064×2752), and the largest Apple Watch simulator (Ultra, 410×502 or 422×514). Flows in `mobile/device-check/store/` with `clearState: true` type four sample notes (a shopping list, a styled meeting note, a voice-style note, a shared link), then capture: Home, a note open, search, Settings. The watch job launches the watch app on its paired simulator and takes its main screen with `xcrun simctl io <watch> screenshot`. Output: an artifact `store-screenshots/en-CA/` named in deliver's order (`1_iphone_home.png` …). At build, the screenshots are downloaded and committed under `mobile/ios/fastlane/screenshots/en-CA/`. **Alternative:** Flutter widget-test goldens on Linux. Rejected: no iOS status bar, wrong fonts in system parts, and the SwiftUI watch app cannot be drawn. **Alternative:** take screenshots in every release run. Rejected: adds time and a flaky step to the release gate for pictures that rarely change.

Health, Location and Photos folders stay out of the screenshots: a simulator has no real data, and we must show no person's real data.

### Privacy answers: a file plus one pass by hand

The App Store Connect API has no App Privacy endpoints; fastlane's `upload_app_privacy_details_to_app_store` needs an Apple ID session, which CI does not have. So `mobile/ios/fastlane/app_privacy_details.json` (fastlane's format) is the record, and the answers are set once by hand in App Store Connect (Matthew, in Safari). All data *linked to the user*, *App Functionality* only, *not used for tracking*:

| Apple category | Why |
|---|---|
| Health, Fitness | HealthKit types, workouts, when Health is on |
| Precise Location | location history, stays and trips |
| Email Address | sign-in |
| Photos or Videos | photos sent with Photos on; files on notes |
| Other User Content | notes, calendar events |
| User ID, Device ID | the account and the phone's key |

Not collected: audio (recordings stay on the phone), contacts, browsing, purchases, diagnostics (no crash reporter sends to us).

### One-time App Store Connect settings through the API

Price free (`appPriceSchedules` with the 0.0 point, base territory CAN) and availability in all territories; `appStoreReviewDetail` contact from the memory store, never from the repo. A scratch script does these once; the README lists them under *Set by hand in App Store Connect*.

### A test for the page files

`scripts/app-store-listing.test.mjs` (node:test, runs in the existing Test workflow): required files exist; Apple limits (name 30, subtitle 30, keywords 100 in total, promotional text 170, description 4000); URLs are https; categories are valid `deliver` names; `rating.json` keys are known; each screenshot is a PNG of an accepted size per device folder, at least one and at most 10 each; no email address or phone number in any metadata file. `scripts/product-name.test.mjs` adds the metadata files to its list.

## Risks / Trade-offs

- [Another app holds the name *Relay Everything*] → `deliver` fails at the release check with Apple's message; fall back to *Relay Everything: Notes* and ask Matthew.
- [`deliver` refuses to change the version `1.0` to `1.0.0`] → the release check shows it; then change the version string once through the API.
- [Apple rejects for health data use (guideline 5.1.3) or asks for a demo account] → the reviewer note explains; the answer goes back through App Store Connect, and a fix is a normal change.
- [Watch simulator screenshots are hard to script] → if `simctl` cannot take the watch screen, take it once in the device check run with Claude and commit it; the test still checks its size.
- [The privacy answers in App Store Connect drift from the file] → the README's release steps say to compare them before a tag that adds a data kind.

## Migration Plan

1. Build and publish this change. 2. Run the release check from `main`; it verifies the page. 3. Matthew pushes `v1.0.0` (or asks). Rollback: the page files can be reverted; App Store Connect keeps the last sent page until the next release.
