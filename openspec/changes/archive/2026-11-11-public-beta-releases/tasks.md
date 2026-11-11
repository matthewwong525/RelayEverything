# Tasks

## 1. The public beta lane and job

- [x] 1.1 Add `PUBLIC_BETA_GROUP` and a `public_beta` lane (`version:`, `build:`, `notes:`) to `mobile/ios/fastlane/Fastfile`: `connect_key`, `wait_for_processing`, find the group (fail with the README steps if missing), add the build unless it is in the group, write `whatsNew` for the primary locale, submit for beta review unless already submitted; Apple's *another build waits for review* refusal becomes `UI.important` and a clean return
- [x] 1.2 Add a `sent` output to the `testflight` job and the `mobile-ios.yml` workflow call: `true` only when the *TestFlight* step ran and passed
- [x] 1.3 Add the Ubuntu job `public-beta` to `mobile-ci.yml`: needs `[plan, ios]`, only in mode `beta` with `needs.ios.outputs.sent == 'true'`, 60-minute timeout, writes the head commit's subject without `(#n)` to `$RUNNER_TEMP/what-to-test.txt`, runs `bundle exec fastlane public_beta` with the App Store Connect secrets
- [x] 1.4 Extend `scripts/app-release.test.mjs`, which already reads the workflow: `public-beta` runs only in beta mode, only when `ios` sent, and never in a release or release check; the `Fastfile` holds the `public_beta` lane
- [x] 1.5 The `public_beta` lane waits, within the same 75-minute deadline, until the build's beta detail is processed (`Build.get`, `build_beta_detail.processed?`); then it submits only from `READY_FOR_BETA_SUBMISSION`, returns with a message for a state already sent (waiting for or in beta review, approved, rejected, in or ready for beta testing), and fails naming any other state
- [x] 1.6 Move the wait into a new workflow `.github/workflows/mobile-public-beta.yml` (*Mobile public beta*, `workflow_dispatch` with `version`, `build`, `sha`; group `mobile-public-beta`, never cancelled; 90-minute timeout; checkout at `sha`); the `public-beta` job in `mobile-ci.yml` keeps its `needs` and `if` but only runs `gh workflow run mobile-public-beta.yml` with `actions: write`; `scripts/app-release.test.mjs` checks both
- [x] 1.7 The timeouts agree: the `Fastfile` comment and `mobile/README.md` say the lane waits at most 75 minutes inside the new workflow's 90; the README's *Public beta* part and `wiki/open-source.md` describe the new workflow

## 2. Website and docs

- [x] 2.1 `site/src/content/docs/index.mdx`: the *iPhone (TestFlight)* button opens `https://testflight.apple.com/join/hSfKtWB7`, labelled *iPhone (public beta)*
- [x] 2.2 `site/src/content/docs/start/install.md`: the iPhone steps open the public link, with no invite
- [x] 2.3 `mobile/README.md`: a *Public beta* part under the release steps: what each main build does, what is set by hand at Apple (group, description, contact) and how to change it, and what is left before the first App Store version (listing, screenshots for iPhone, iPad and Apple Watch, privacy answers, final policy)
- [x] 2.4 `wiki/open-source.md` *Phone builds* and the AGENTS.md *Phone builds* bullet: a main build also goes to the public beta

## 3. Checks

- [x] 3.1 `node --test scripts/app-release.test.mjs`, `node scripts/product-name.test.mjs`, `node scripts/public-check.mjs`, and the site's own tests

## After the publish

`/ship` does these after the merge and reports them: watch main's *Mobile public beta* run add the build to *Public beta* and send it to beta review (or note the waiting review), then run `node scripts/publish-relay-site.mjs` and `node scripts/publish-relay-server.mjs` and report both `result=` lines.
