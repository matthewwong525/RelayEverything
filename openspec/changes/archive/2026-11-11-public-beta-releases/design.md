# Design

## Context

`mobile-ci.yml` calls `mobile-ios.yml` for main (mode `beta`), a release and a release check. Its `testflight` job runs `fastlane beta`, which uploads with `skip_waiting_for_build_processing: true`, and its *Newest on main* step skips the upload when a newer commit on main changes `mobile/`. The `release` job already runs fastlane on Ubuntu with the App Store Connect key, and `wait_for_processing` in the `Fastfile` already waits for Apple.

At Apple, on 2026-11-11, by hand with the App Store Connect API: the external group *Public beta* (public link on, feedback on), the `en-CA` beta description with the live `/privacy/` page as its privacy link, the beta review contact, and build 270 in beta review.

## Goals / Non-Goals

**Goals:** each sent beta from main joins *Public beta* and goes to beta review with no hand step; the site links to the public beta.

**Non-Goals:** the App Store listing, screenshots and `v1.0.0`; setting the beta description or contact from the repository; a public beta for a release or release check.

## Decisions

- **A `public_beta` lane in the `Fastfile`, run by a new Ubuntu workflow `mobile-public-beta.yml` that the `public-beta` job in `mobile-ci.yml` starts.** The job needs `[plan, ios]`, runs only in mode `beta` and only when `ios` reports `sent == 'true'`, and only runs `gh workflow run mobile-public-beta.yml --ref main` with the version, build and commit (`actions: write`). The lane reuses `connect_key` and `wait_for_processing`, then uses Spaceship to find the group by name, add the build, write the build's `whatsNew` for the app's primary locale, and post a beta review submission. Alternative: `upload_to_testflight(distribute_external: true)` in the Mac job. Rejected, because waiting on a Mac runner for up to 30 minutes costs about ten times an Ubuntu runner.
- **The wait has its own workflow and group, `mobile-public-beta`, never cancelled.** Main's runs of `mobile-ci.yml` share one group that is never cancelled, so a job there that waits up to an hour for Apple would hold up main's next run. The new workflow (`workflow_dispatch` with `version`, `build`, `sha`) checks out `sha`, has a 90-minute timeout, and runs one build at a time. Alternative: a `workflow_run` trigger. Rejected, because it can not tell the run's version and build, or whether `ios` sent.
- **One 75-minute deadline (`PROCESSING_WAIT`) covers two waits:** the build's `processing_state` reaching `VALID`, then its beta detail being processed (`Build.get`, `build_beta_detail.processed?`), as fastlane's own pilot waits. The workflow's 90 minutes cover it and the setup.
- **The beta detail's external state decides the submission.** `READY_FOR_BETA_SUBMISSION` sends. A state already sent (`WAITING_FOR_BETA_REVIEW`, `IN_BETA_REVIEW`, `BETA_APPROVED`, `BETA_REJECTED`, `IN_BETA_TESTING`, `READY_FOR_BETA_TESTING`) is a message and a clean return. Any other state, such as `MISSING_EXPORT_COMPLIANCE`, `PROCESSING_EXCEPTION` or `EXPIRED`, fails the run naming it. The states come from Spaceship's `BuildBetaDetail::ExternalState`, read when the lane runs.
- **`mobile-ios.yml` gets a `sent` output** from the `testflight` job: `true` when its *TestFlight* step ran and passed. A workflow-call output is the only way for the caller to know the *Newest on main* step skipped.
- **What to Test is the head commit's subject without its `(#n)`**, cut to 4,000 characters, passed as `notes:` from a file in `$RUNNER_TEMP`, as the `submit` lane takes its notes.
- **The refusal for a build already waiting is a notice.** Spaceship raises Apple's error; the lane matches the *another build is in review* error and returns with `UI.important`. Any other error fails the job. Rerunning the job is safe: a build already in the group or already submitted is skipped.
- **The group name is a constant `PUBLIC_BETA_GROUP = "Public beta"`** in the `Fastfile`; a missing group fails the job with the steps in `mobile/README.md`.
- **The site uses the public link `https://testflight.apple.com/join/hSfKtWB7`**, which holds no private detail, so the site guard passes.

## Risks / Trade-offs

- [The first build of a new version waits for a full beta review, a day or more] → testers keep the last approved build until then; nothing fails.
- [Apple's error text for a waiting review changes] → the job fails with Apple's text, and a rerun after the review sends it; the match lives in one helper.
- [A public link lets anyone install the app] → signed out, the app makes no network call, and the shared server stays invite-only.
