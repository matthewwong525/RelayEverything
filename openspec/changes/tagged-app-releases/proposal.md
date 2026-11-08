# Release the phone app with a tag

**Status:** built, publishing
**Branch:** tag-triggered-release-pipeline
**Open questions:** none

## Why

Today every push of the phone app, on any branch, sends an iPhone build to TestFlight. A branch build can then be newer than main, so your phone gets a version that is old or misses work that is already live. Run 98, from a branch, is TestFlight's newest build now, above main's run 96. There is also no way to make a real store release: nothing sends the app to the App Store, and no release notes exist.

## What Changes

**What you get**

- **Betas come only from main.** After a change lands on main, its iPhone build goes to TestFlight and its Android file goes on GitHub as a *pre-release*. A branch still runs the tests and builds both apps, so a broken build shows before it lands, but it sends nothing to TestFlight. When two changes land close together, only the newest one sends, so an older build never comes after a newer one.
  ```mermaid
  flowchart TD
    B[Branch push] --> X[Test + build, send nothing]
    M[Lands on main] --> N{Newest?}
    N -->|yes| TF[TestFlight + pre-release]
    N -->|no| S[Skip]
  ```
- **A tag makes a real release.** You put a tag such as `v1.1.0` on a commit on main, and nothing else. The tag sets the version. The release runs the full test, then sends the iPhone app to Apple for review. Apple puts it live in the App Store as soon as it approves. The Android file goes on GitHub as the newest release, so the website's *Android app* link opens it.
  ```mermaid
  flowchart TD
    T["Tag v1.1.0 on main"] --> C[Tests]
    C --> A[Builds + voice check]
    C --> R[iPhone tour]
    A --> G{All passed?}
    R --> G
    G -->|yes| S[Send to App Store review]
    S --> L[GitHub release + notes]
    L --> P[Mark each change]
    G -->|no| F[Stop: nothing sent]
  ```
- **The full test before a release.** The app's tests, both builds, the check that voice notes still get their words, and the fixed iPhone tour on a simulator: open the app, write a note, open Settings. Each step of the tour must pass. Claude does not run. One failure stops the release before anything goes to a store.
- **Release notes, written for you.** The release lists each change to the phone app since the last release, grouped by kind, each with a link. The same list goes to the App Store as *What's New*. Changes to the server or the website are not listed, because they go live on their own each publish.
  ```text
  Relay Everything 1.1.0

  New
  - Edit notes like Apple Notes (#55)
  - A recording from Shortcuts becomes a voice note (#57)
  Fixes
  - Sign iPhone builds with one saved certificate (#54)

  Full list: v1.0.0...v1.1.0
  ```
- **Each change knows its release.** Each pull request in the release gets the label *released* and a short comment, such as *Released in Relay Everything 1.1.0* with the link.
- **Plain refusals.** A tag that is not on main, or a version that is not higher than the last release, stops at once and says why.

**What changes in how you work**

- **To release, you tag.** In GitHub, open *Releases*, then *Draft a new release*, then type a new tag such as `v1.1.0` on main. Or ask me to tag it. Everything after that is automatic.
- **Betas use the next version.** After `v1.1.0`, the betas from main are `1.1.1`, because Apple takes no new TestFlight builds for a version that is already live.
- **The Android file gets a real signing key.** Today it signs with a test key. A phone that has the old file must remove it once, then install the new one. After that, each update installs over the last.

**What you do yourself, once, before the first real release**

- **Fill in the App Store page in App Store Connect**: the description, screenshots, support and privacy addresses, age rating, and the privacy answers. Apple needs these for its first review, and they stay for later releases.
- **Finish the privacy policy.** The policy on the website is still a draft. Apple needs a final one at its address.

**What is left out, and why**

- **Google Play.** You chose the GitHub file for now. Play can join the release later, in a change of its own.

## What the build needs

- **Apple keys and the signing certificate**: Ready. They are in the repository's secrets and in `.env`.
- **The Android signing key**: Ready. The build makes it once, saves it in `.env` and in the repository's secrets, and never shows it.
- **The iPhone signing fix (pull request #54)**: Ready once it is live. The build starts from main after #54 lands.

## Capabilities

### New Capabilities

- `relay-app-releases`: a version tag on main tests, builds and submits the phone app to the App Store, makes the GitHub release with notes from the changes to `mobile/`, and marks each included pull request.

### Modified Capabilities

- `relay-app-builds`: TestFlight and the Android pre-release come only from `main`, newest commit only; a branch push builds both apps but uploads nothing.

## Impact

- `.github/workflows/mobile-ci.yml`: a `v*` tag trigger, a version job, a release job, and main-only, newest-only uploads.
- `.github/workflows/mobile-android.yml`, `.github/workflows/mobile-ios.yml`: version and mode inputs; Android pre-release on main, signed release on a tag.
- `.github/workflows/mobile-device-check.yml`: callable for the fixed tour alone.
- `mobile/ios/fastlane/Fastfile`: an upload-only path for branches, and a `submit` lane for App Store review.
- New `scripts/app-release.mjs` and its test: version from tag, next beta version, release notes and the PR list.
- The label *released*, and GitHub secrets for the Android upload key.
- Docs: `mobile/README.md`, `wiki/open-source.md`, the `AGENTS.md` phone builds line, and the website's install page.

## Decision log

- **2026-11-08** — Asked what a tagged release does for Android, with no Google Play account → chose the GitHub file only for now; Play waits for a later change.
- **2026-11-08** — Asked what the full test on a release runs → chose the app's tests, both builds, the voice check, and the fixed iPhone simulator tour, with no Claude step.
- **2026-11-08** — Asked how to go on beside the iPhone signing fix (#54) → chose to plan here and build from main after #54 is live.
- **2026-11-08** — Asked (in a message) that TestFlight get builds only after a change hits main, never from a pull request, with the newest version each time → planned as main-only, newest-only betas.
- **2026-11-08** — Assumed: Apple puts the app live as soon as it approves, because you said you should not need to do anything after the tag.
- **2026-11-08** — Assumed: the tag looks like `v1.1.0` and sets the version, so you never edit a version number by hand.
- **2026-11-08** — Assumed: release notes list only the changes to the phone app, because the server and website go live on each publish, not with a release.
- **2026-11-08** — Assumed: branches still build and sign the iPhone app but never upload it, so a build break shows before it lands; branch work on a real iPhone uses the simulator check instead.
- **2026-11-08** — Assumed: a release refuses to use the Android test key, because a file signed with a test key could never update to a properly signed one.
- **2026-11-08** — Assumed: the build makes the Android signing key itself and stores it as a secret, since it needs no account and no payment.
- **2026-11-08** — Assumed: the GitHub release titles say *Relay Everything*, not *Relay for Android*, by the product name rule.
- **2026-11-08** — Assumed: a release-check run uses the next beta version (the newest release with its patch number one higher), so its test build joins the betas' version in TestFlight and makes no new version there.
- **2026-11-08** — Assumed: the Android and iPhone build files no longer start by hand on their own, because each needs the version that Mobile CI works out first; *Run workflow* on Mobile CI builds both instead.
- **2026-11-08** — Assumed: a release stops, with the missing names, when the App Store Connect key is not in the secrets, so the Android file never goes out without the iPhone app.
- **2026-11-08** — Assumed: the iPhone share card's Swift tests still run in a release's tour, and a failure stops the release like a tour step.
- **2026-11-08** — Assumed: the first release's GitHub notes add one line for Android phones with an older file: send your notes, remove the app once, then install.
- **2026-11-08** — Assumed: a release made on GitHub's *Releases* page gets the `.apk` and the notes from the run; if the run fails, the person deletes that release.
- **2026-11-08** — Assumed: a release check runs only from `main`, because its iPhone build goes to TestFlight with the betas; `app-release.mjs version` refuses it from a branch with the reason, and the release check after publish runs with `--ref main`.
- **2026-11-08** — Assumed: the first version sent to App Store review gets no *What's New*, because Apple refuses it on an app's first version; later versions get the notes.
- **2026-11-08** — Assumed: a release or a release check stops with the missing names when an iPhone signing secret is missing; a branch or a beta still ends with a notice.
- **2026-11-08** — Check: `.github/workflows/mobile-ci.yml` changes its triggers and jobs (adds `v*` tags, a release check, and the plan, tour and release jobs), because the release needs them; no check is removed, and a tag now runs more checks than a push.
- **2026-11-08** — Check: `.github/workflows/mobile-ios.yml` stops the TestFlight upload from branches and drops its own manual start, because betas come only from main (the plan) and the version now comes from Mobile CI's plan job; the signed build and the speech check still run on every branch.
- **2026-11-08** — Check: `.github/workflows/mobile-android.yml` drops its own manual start and makes main's file a pre-release, because the version comes from Mobile CI's plan job and only a tag makes the latest release; it now refuses a release with no upload key.
- **2026-11-08** — Check: `.github/workflows/mobile-device-check.yml` skips the Claude steps when a release calls it for the tour alone, because the plan chose the fixed tour with no Claude step as the release gate; the tour now fails on any failed step, not only the first.
- **2026-11-08** — Check: `app/package.json` adds `scripts/app-release.test.mjs` to the test list, because the release script needs its tests to run; nothing is taken out.
- **2026-11-08** — Assumed: the first main run and the release check are checked right after publish, not as tasks, because both need this change on main first.
