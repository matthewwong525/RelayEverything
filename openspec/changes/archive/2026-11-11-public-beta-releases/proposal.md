# Keep the public beta on the newest build

**Status:** ready-to-ship
**Branch:** publish-app-store-beta
**Open questions:** none

## Why

Relay Everything now has a public beta: anyone with the link can install the iPhone app through TestFlight. On 2026-11-11 the beta group, its description and Apple's reviewer contact were set up by hand, and build 270 went to Apple's beta review. But each new build from main goes only to the team's own TestFlight group. Without this change, the public beta stays on build 270 until someone adds each new build by hand.

## What Changes

- **Each new build reaches the public beta.** When a change lands on main, its iPhone build goes to TestFlight as today. Then, after Apple has processed it, the build also goes to the *Public beta* group, with the change's title as *What to Test*, and it goes to Apple's beta review. Apple usually lets later builds of the same version through quickly. Nothing else changes for you.
  ```mermaid
  flowchart TD
    M[Lands on main] --> T[TestFlight: team]
    T --> P{Apple processed it?}
    P -->|yes| G[Public beta group]
    G --> R[Beta review]
    R --> L[Testers with the link get it]
  ```
- **A busy review is not a failure.** If an earlier build is still waiting for beta review, Apple can refuse the new one. The run then notes it and passes, and the next change to the app sends again.
- **The website links to the beta.** The home page's *iPhone* button and the iPhone install steps open the public TestFlight link. You no longer need an invite from the server's owner to get the app.
  ```text
  iPhone
  1. Install TestFlight from the App Store.
  2. Open https://testflight.apple.com/join/hSfKtWB7
  3. Tap Accept, then Install.
  ```
- **The steps are written down.** The phone app's release page says how the beta works, what was set up by hand at Apple, and what is still left before the first App Store version.

**Non-goals:** the App Store listing and the first `v1.0.0` release. That needs screenshots, the full description, age rating, Apple's privacy answers and a final privacy policy, and it is a later change of its own. The release check and a tag release still send nothing to the public beta.

## What the build needs

- **Apple's key**: Ready. `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` are in the repository's secrets and in `.env`.
- **The Public beta group and its link**: Ready. Made on 2026-11-11, with the beta description and the reviewer contact.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-app-releases`: a beta from main also goes to the external *Public beta* TestFlight group and to beta review.
- `relay-website`: the iPhone install steps and the home page link to the public TestFlight beta.

## Impact

- `mobile/ios/fastlane/Fastfile`: a new `public_beta` lane.
- `.github/workflows/mobile-ios.yml`: a `sent` output; `.github/workflows/mobile-ci.yml`: a new `public-beta` job after `ios`, in beta mode only, that starts the new `.github/workflows/mobile-public-beta.yml`.
- `site/src/content/docs/index.mdx`, `site/src/content/docs/start/install.md`: the public link.
- `mobile/README.md`, `wiki/open-source.md`: the beta steps.

## Decision log

- **2026-11-11** — Asked which route to take first: a public TestFlight beta, the App Store, or both → chose the public beta first.
- **2026-11-11** — Asked who Apple's reviewer contact is → Matthew Wong, with his email and phone. They stay in App Store Connect only, never in the repository.
- **2026-11-11** — Assumed: the beta description, review contact and group stay set by hand at Apple, and the run only adds builds, because they change rarely and the App Store listing works the same way.
- **2026-11-11** — Assumed: the beta's privacy link is the live *Privacy* page, not the draft policy, because the draft says it is not in force.
- **2026-11-11** — Assumed: the public link goes on the website now, because a stranger can use the app with no sign-in and the landing page was waiting on this link.
- **2026-11-11** — Assumed: the wait for Apple's processing runs on a cheap Ubuntu job, not the Mac build, because the wait can take 30 minutes.
- **2026-11-11** — Assumed: a beta review refused because another build waits is a notice, not a failure, because the next build catches up.
- **2026-11-11** — Assumed: the wait for Apple runs in its own workflow, `mobile-public-beta.yml`, which main's `public-beta` job only starts, because a job in main's Mobile CI run holds main's queue for up to an hour and delays the next change's builds.
- **2026-11-11** — Check: `.github/workflows/mobile-ci.yml` loosens no check: it only adds the `public-beta` job after `ios`, and every test and build job keeps its settings, because the scan flags any edit to a workflow file.
- **2026-11-11** — Check: `.github/workflows/mobile-ios.yml` loosens no check: it only adds a `sent` output and a step id, because the scan flags any edit to a workflow file.
- **2026-11-11** — Check: `.github/workflows/mobile-public-beta.yml` loosens no check: it is a new workflow that only adds builds to the public beta, because the scan flags any new workflow file.
- **2026-11-11** — Assumed: the watch of the first public beta run and the site publish happen after the merge, in `/ship`'s report, not as a task, because a task must pass before the merge.
- **2026-11-11** — Assumed: archive checkpoint: built, reviewed (three findings fixed: wait for beta processing, own workflow for the wait, 90-minute limit), and archived for publish.
