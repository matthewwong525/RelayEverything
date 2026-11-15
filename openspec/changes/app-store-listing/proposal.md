# Fill in the App Store page for the first release

**Status:** building
**Branch:** app-store-listing
**Open questions:** none

## Why

The iPhone app is ready for the App Store, but its page in App Store Connect is empty: no description, no screenshots, no category, no age rating, no privacy link and no privacy answers. Apple refuses review without them. The page also shows the name *RelayEverything*, with no space. Until this change, a `v1.0.0` tag would build and test the app, then stop at Apple.

## What Changes

- **The store page's words live in the repo.** The name *Relay Everything*, a subtitle, the description, keywords, category, age rating, support link and the privacy link (the live [Privacy page](https://relayeverything.com/privacy/)) are files next to the iPhone app. To change the page later, you change a file, like any other change. No clicks in App Store Connect.
  ```text
  Relay Everything
  Your notes, health and places
  ─────────────────────────────────────────────
  Write a note, say it, or share it from any app.
  It stays on your phone until you turn on sending.
  Then Relay Everything sends your notes, health,
  calendar, places and photos to your own space,
  your own webhook, or the AI apps you connect.
  ...
  Category: Productivity · Also: Utilities · Free
  ```
- **Real screenshots for iPhone, iPad and Apple Watch.** A Mac on GitHub opens the app on the large iPhone, the large iPad and the watch simulators, writes a few sample notes, and takes plain pictures of the main screens, with no added words. The pictures are kept in the repo. You run it again only when the app looks different. These are today's device-check pictures; the store's are the same screens on the larger iPhone:
  ```picture
  Home: pictures/timeline.png
  Settings: pictures/settings.png
  ```
- **Each release sends the page with the app.** When you push a `v` tag, the release first sends the words and screenshots to Apple, then sends the build to review, as today. The release check sends nothing; it only checks that Apple would take the page.
  ```mermaid
  flowchart TD
    T["v1.0.0 tag"] --> F[Full test]
    F --> P[Send store page]
    P --> R[App Store review]
    R --> L[Live]
  ```
- **Apple's privacy answers are written down, then set once.** The answers say what the app collects: notes, health, location, photos, email, and the phone's key. Each is linked to you, used only to run the app, and never used for tracking or ads. Apple has no way for a script to set these, so I set them once in App Store Connect through the browser signed in as you. The file in the repo is the record. If what the app collects changes, you update the file and the answers.
  ```text
  Used to track you   None
  Linked to you       Health · Fitness
                      Precise location · Email
                      Photos · Other user content
                      User ID · Device ID
  Used for            App functionality only
  ```
- **The one-time settings are set.** I also set the app as free in every country, the reviewer contact and the reviewer note. The note says the app works with no account, and gives the steps to try sign-in. The contact's email and phone stay in App Store Connect, never in the repo, because the repo is public.
- **The release page says what is left.** The phone app's README no longer lists the missing store page. It says where each part of the page lives and how to take new screenshots.

**Not in this change:** the `v1.0.0` tag itself. You push it, or ask me, after this change is live. Also not here: the website's *iPhone* button. It moves from the public beta to the App Store only after Apple approves the app. The lawyer-read privacy policy can replace the current Privacy page later, at the same link.

## What the build needs

- **Apple's key**: Ready. `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` are in the repository's secrets and in `.env`. I used it to read the empty page today.
- **Your Apple sign-in in the browser, for the privacy answers**: Ready. The browser was trusted on 2026-11-06. If Apple asks for a code again, I'll ask you then.
- **The reviewer contact**: Ready. You gave it on 2026-11-11 for the public beta.
- **The seller name**: Ready. Your developer account is an individual one, so Apple shows your own name as the seller. A company name would need a new organization membership, which is not part of this change.

## Capabilities

### New Capabilities
- `app-store-listing`: the App Store page's words, screenshots, age rating, category and privacy answers kept in the repo, and the workflow that takes the screenshots.

### Modified Capabilities
- `relay-app-releases`: a release now sends the store page from the repo before it submits the build, and the release check verifies the page without sending it. Before, a release never changed the page.

## Impact

- `mobile/ios/fastlane/`: new `metadata/en-CA/` text files, `screenshots/en-CA/`, `rating.json`, `app_privacy_details.json`, and a `listing` lane in the `Fastfile`; `submit` stays as is.
- `.github/workflows/mobile-ci.yml`: the release job runs `fastlane listing` before `submit`; the release check runs it with `verify_only`.
- New `.github/workflows/mobile-store-screenshots.yml` and Maestro flows in `mobile/device-check/store/`.
- New `scripts/app-store-listing.test.mjs`; `scripts/product-name.test.mjs` adds the metadata files.
- `mobile/README.md`, `wiki/open-source.md`.
- Outward, once: App Store Connect price and availability, reviewer contact, privacy answers.

## Decision log

- **2026-11-15** — Asked whether to start on the App Store page (store text, screenshots, privacy answers) → chose to start now.
- **2026-11-15** — Asked where the store page's text and pictures live → chose in the repo, sent by each release.
- **2026-11-15** — Asked which privacy link the store page uses → chose the current live /privacy/ page; the lawyer-read policy replaces it later at the same link.
- **2026-11-15** — Asked how the screenshots look → chose plain app screens, with no captions.
- **2026-11-15** — Assumed: the store name is *Relay Everything*, not the current *RelayEverything*, because the project rule forbids any other spelling in text a person reads.
- **2026-11-15** — Assumed: categories Productivity and Utilities, because the app is a notes and data-sending tool, not a health app.
- **2026-11-15** — Assumed: the support link is the GitHub issues page, because the site guard refuses email addresses and the /terms page already names GitHub issues as a way to reach us.
- **2026-11-15** — Assumed: the seller name needs no step, because an individual developer account shows the person's own name.
- **2026-11-15** — Assumed: screenshots come from simulators on a GitHub Mac, not from Flutter screen tests, because a screen test can't draw the SwiftUI watch app or the iPhone's own parts.
- **2026-11-15** — Assumed: Apple's privacy answers are set once in the browser, with the repo file as the record, because Apple's API has no way to set them.
- **2026-11-15** — Assumed: the release check runs `fastlane listing verify_only:true` as fastlane's own screenshot check plus a read of App Store Connect, sending nothing, because deliver's `verify_only` checks only an app binary, not the page. Apple checks the words, such as a taken name, only at the release.
- **2026-11-15** — Assumed: the screenshot workflow runs from any branch and also by the label *store screenshots* on a pull request, not from `main` only, because GitHub starts a new workflow by hand only once it is on `main`, and this change must hold the pictures. The run sends nothing.
- **2026-11-15** — Assumed: the screenshots show five screens, Home, the notes list, a note, search and Settings, adding the notes list to the four in the design, because it shows the most of the app.
- **2026-11-15** — Check: `.github/workflows/mobile-ci.yml` adds the step *App Store page* to the release job before *App Store review*, and turns no check off, because a release must send the page from the tagged commit before it submits the build.
- **2026-11-15** — Check: `.github/workflows/mobile-store-screenshots.yml` is a new workflow that only takes pictures and sends nothing, and turns no check off, because the store needs real simulator screenshots for iPhone, iPad and Apple Watch.
- **2026-11-15** — Check: `app/package.json` adds `../scripts/app-store-listing.test.mjs` to the test chain and turns no check off, because the page files need their Apple limits checked on each change.
- **2026-11-15** — Saved mid-build, with the screenshots, the one-time App Store Connect settings and the final checks still open, because the screenshot workflow starts from a label on the pull request.
