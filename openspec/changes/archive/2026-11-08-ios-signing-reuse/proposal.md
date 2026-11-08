# Proposal: Reuse one iPhone signing certificate in each build

**Status:** ready-to-ship
**Branch:** iphone-build-signing
**Open questions:** none

## Why

Each iPhone build on GitHub starts on an empty Mac, so Xcode makes a new Apple certificate on every run. After about 11 runs the Apple account is full, and the TestFlight build stops: main failed this way at 62cb18b. We cleaned the account by hand twice; it fills again.

## What Changes

- **One saved certificate signs every iPhone build.** We make one Apple Distribution certificate one time, and keep it in the repository's secrets, never in the code. Each build loads it, signs with it, and makes no new certificate. The certificate lasts one year; a short step on this computer makes the next one.
  ```mermaid
  flowchart TD
    S["Saved certificate"] --> M["Build Mac"]
    K["Apple key"] --> P["Get app profiles"]
    P --> M
    M --> T["TestFlight"]
  ```
- **The app profiles come from Apple each run.** The build asks Apple for the App Store profiles of the app and of its share sheet, made for the saved certificate. Apple gives the same ones each run, and makes a new one only when one is missing or old. Nothing about profiles goes in secrets.
- **A clear notice when the certificate is missing.** Until the certificate is in the secrets, the iPhone build stops with a notice that says which secret to add, as it does now for a missing Apple key.
- **One step for you on developer.apple.com, only if the account is still full.** Open Certificates, and revoke each *Apple Development: Created via API* certificate. These came from old builds; no person uses them. A revoked certificate can't be brought back. On 2026-11-07, Apple's list showed only your *Developer ID Application* certificate, so this step may not be needed: the build tells us.

## What the build needs

- **App Store Connect key (Admin)**: Ready, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` and `APPLE_TEAM_ID` are in `.env` and in the repository's secrets.
- **The saved certificate**: Ready, the build makes it on this computer with the Apple key and sends it straight to the repository's secrets and `.env`. It never goes in chat or in the code.
- **Revoke old certificates on developer.apple.com**: Ready for now, Apple listed no development certificates on 2026-11-07. If the first build still says the account is full, the build stops and asks you, with the link.

## Capabilities

### New Capabilities

### Modified Capabilities
- `relay-app-builds`: the iPhone build signs with one saved certificate and never makes a new one.

## Impact

- `mobile/ios/fastlane/Fastfile`: manual signing with the saved certificate and fetched App Store profiles; no `-allowProvisioningUpdates`.
- `.github/workflows/mobile-ios.yml`: two new secrets, `IOS_DIST_CERT_P12` and `IOS_DIST_CERT_PASSWORD`, in the gate and the job's environment.
- New `scripts/ios-signing-cert.mjs`: makes the certificate through the App Store Connect API and stores it with `gh secret set`.
- `.env.example`, `mobile/README.md`, `wiki/open-source.md` (Phone builds): the new secrets, the yearly renewal, and the revoke step.
- Apple account: one Apple Distribution certificate (Apple allows a small number) and two App Store profiles.

## Decision log

- **2026-11-07** — Assumed: one saved certificate in GitHub secrets, not fastlane `match`, because the repository is public and `match` needs a private store.
- **2026-11-07** — Assumed: profiles are fetched from Apple each run, not saved, because that adds no secrets and renews itself.
- **2026-11-07** — Assumed: the assistant makes the certificate on this computer with the Apple key already in `.env`, because on 2026-11-06 Matthew let it handle this Apple key, and the values then never pass through chat.
- **2026-11-07** — Assumed: the revoke step is needed only if the first build still says the account is full, because Apple's list showed no development certificates on 2026-11-07.
- **2026-11-07** — Assumed: the script keeps a saved certificate that Apple still lists with more than 30 days left, and `--renew` forces a new one, because a second run must not spend one of Apple's few distribution places.
- **2026-11-07** — Assumed: the script's test runs in `app/`'s `npm test` beside the other script tests, and `.env.example` now says the key needs Admin, as `wiki/open-source.md` already did.
- **2026-11-07** — Check: `.github/workflows/mobile-ios.yml` skips the iPhone build, with a notice that names the secret, when `IOS_DIST_CERT_P12` or `IOS_DIST_CERT_PASSWORD` is missing, because a build without the saved certificate can't sign and must not fall back to making a new one.
- **2026-11-07** — Check: `app/package.json` adds `scripts/ios-signing-cert.test.mjs` to `npm test`; nothing is removed, because the certificate script's test must run in CI like the other script tests.
- **2026-11-07** — Assumed: the script checks `gh auth status` before it asks Apple for a certificate, and writes both `.env` lines before any GitHub secret, because a failed save after Apple makes one must not leave a `.p12` with the wrong password.
- **2026-11-07** — Assumed: the build passes `DEVELOPMENT_TEAM` again, because a CocoaPods resource bundle can need a team, and the two app targets still sign manually.
- **2026-11-08** — Checkpoint: built and reviewed (4 review fixes made); saved to run the iPhone build on the branch for tasks 4.2 and 4.3.
- **2026-11-08** — Checked: run 42429382593 on this branch imported the saved certificate, made the two App Store profiles, and uploaded to TestFlight. Apple then listed 7 *Created via API* development certificates; the 2 made on 2026-11-08 came from runs 42428573631 (main) and 42428853209 (staging-webhook-catchup), which still used the old Fastfile, and this run never passed `-allowProvisioningUpdates`. The old ones are left; the account is not full, and no new ones come after the merge.
- **2026-11-08** — Archive checkpoint: tasks all done; archived for publishing.
