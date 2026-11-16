# The Mac app updates itself, and the website's Mac download works

**Status:** building
**Branch:** mac-app-updates
**Open questions:** none

## Why

Today the Mac app can't update itself. To get a new version, you must remember to download it again from the website. Also, there is no Mac download at all yet: no build has a signed Mac app, and the website's *Download for Mac* link shows "not found".

## What Changes

- **The app tells you when a new version is ready.** When the app opens, and once a day while it stays open, it checks for a new version. If it finds one, the Mac's usual update window opens, with what is new and three buttons: *Install Update*, *Remind Me Later* and *Skip This Version*. *Install Update* gets the new version, closes the app, puts the new version in its place and opens it again. Your notes, your sign-in and your settings stay.
  ```mermaid
  flowchart TB
    O[App opens] --> C{New version?}
    C -->|no| N[Nothing shows]
    C -->|yes| W[Update window]
    W -->|Install Update| I[Gets it, opens again]
    W -->|Later / Skip| N
  ```

- **You can check yourself.** The *Relay Everything* menu gets *Check for Updates…* below *About Relay Everything*. Settings gets an *Updates* part with the same *Check for Updates…* and a *Get test builds* switch. If you already have the newest version, a short message says so.
  ```picture
  Before: pictures/settings-before.png
  After: pictures/settings-after.png
  ```

- **Full releases by default, test builds if you want them.** With *Get test builds* off, the app offers only full releases. With it on, the app also offers each new test build from the newest work, which can have bugs. When you turn the switch off again, the app stays on the version it has until the next full release is newer.

- **The website's Mac download works, and always gives the newest build.** *Download for Mac* gives the newest signed Mac app, test builds included, before and after the first full release. The *Install* page says the app now updates itself.

- **An update is signed twice.** Apple checks each Mac app before it goes out, as it does today. In addition, each update has its own signature, and the app installs an update only when that signature matches. Thus a changed or false file never installs.

**Non-goals:** the Mac App Store; updates that install with no window (you always click *Install Update*); updates for the iPhone or Android app; Windows and Linux.

## What the build needs

- **A Developer ID certificate**: Ready. It is in the GitHub secrets, and main's last build signed a Mac app with it.
- **The update signing key**: Ready. The build makes it with a script and saves it in `.env` and in the GitHub secrets. Only its public half goes in the app.
- **App Store Connect key, for Apple's check**: Ready. `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` are in the GitHub secrets.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-mac-app`: the Mac app checks for, offers and installs signed updates, with a test-build switch; the website's Mac download is the newest signed build, test builds included.

## Impact

- `mobile/macos/`: Sparkle 2 added to the Runner as a Swift package; a small Swift updater with a method channel; `Info.plist` gets the feed address and the public update key; the entitlements get Sparkle's installer exceptions for App Sandbox.
- `mobile/lib/`: *Check for Updates…* in the Mac menu bar (`lib/mac/mac_app.dart`), an *Updates* row in `SettingsRow` for the Mac only (`lib/screens/settings.dart`), a test-build setting, and a Dart side of the channel. Tests.
- `.github/workflows/mobile-macos.yml` and `mobile-ci.yml`: sign Sparkle's helpers in the right order; after each signed build, write the update feed and put it, with the newest `.dmg`, on one fixed GitHub release, `mac-updates`.
- `scripts/`: a feed writer and an update-key maker, with tests.
- `site/`: the *Install* page and the *On a computer* page; `mobile/README.md`; `.env.example` gets `SPARKLE_ED_PRIVATE_KEY`.
- Server: no change.

## Decision log

- **2026-11-16** — Asked whether to plan in-app updates for the Mac app → chose to plan them.
- **2026-11-16** — Asked whether to make the Mac signing certificate now → chose to make it now. The script tried; Apple refused, because only the account holder can make a Developer ID certificate. It is in *What the build needs*.
- **2026-11-16** — Asked which new versions the Mac app should offer → chose full releases by default, with a *Get test builds* switch in Settings.
- **2026-11-16** — Asked whether to fix the website's *Download for Mac* link too → chose yes: it gives the newest signed build, test builds included.
- **2026-11-16** — Assumed: Sparkle 2 for the updates, because it is the usual Mac update tool, works with App Sandbox, and shows the Mac's own update window; a home-made updater would need its own installer and checks.
- **2026-11-16** — Assumed: the update feed and the newest `.dmg` go on one fixed GitHub release, `mac-updates`, because GitHub gives no fixed address for the newest pre-release, and the website publishes by hand, after the build, so a feed there would be late.
- **2026-11-16** — Assumed: the app checks when it opens and then once a day, and always asks before it installs, because that is how most Mac apps work and nothing changes with no click.
- **2026-11-16** — Assumed: Settings gets an *Updates* part with *Check for Updates…* and the switch, as well as the menu item, because the switch needs a place, and Settings is where a person looks for it.
- **2026-11-16** — Assumed: the *note-toolbar-tables* plan's *Format* menu and this plan's *Check for Updates…* both change the Mac menus and their test; whichever lands second takes in the other's lines, because they add different items and do not conflict in what they do.
- **2026-11-16** — The certificate went to the GitHub secrets: the password through the private link, the `.p12` text on GitHub's secrets page, because the link takes at most 4,096 characters a value. A re-run of main's Mac job made the first signed `.dmg` (Apple accepted it). The `.p12` is not in `.env`; the builds need only the GitHub secrets.
- **2026-11-16** — Assumed: the entitlements name Sparkle's two installer services in full (`com.matthewwong525.relayApp.mac-spks`, `-spki`), not with `$(PRODUCT_BUNDLE_IDENTIFIER)`, because the build signs the app again with the entitlements file as it is, and `codesign` does not fill in Xcode's names.
- **2026-11-16** — Assumed: the `relay/updates` channel has `check`, `checkInBackground` and `setTestBuilds`, and no `canCheck`, because the launch check needs its own quiet call, and Sparkle's own check brings forward a window that is already open, so Dart needs no state for it.
- **2026-11-16** — Assumed: the Settings row and the menu item reach Sparkle through `Relay.checkForUpdates` and `Relay.setTestBuilds`, and `RelayController` holds `MacUpdates`, because Settings gets only the `Relay`, and the phone and the web then need no change. The setting is `Settings.testBuilds`.
- **2026-11-16** — Assumed: what is new in a feed item is the plain-text `whats-new.txt` from `app-release.mjs notes`, as `sparkle:format="plain-text"`, because Sparkle shows the Markdown notes as raw text.
- **2026-11-16** — Assumed: the `mac-feed` job puts the `.dmg` on `mac-updates` only when its build is the newest in the feed, because a release run and a main run can end out of order, and the website must keep the newest file.
- **2026-11-16** — Check: `.github/workflows/mobile-ci.yml` gets the new `mac-feed` job and a `sent` output on `macos-beta`; no check is loosened, because the change only adds a job after the builds.
- **2026-11-16** — Check: `.github/workflows/mobile-macos.yml` signs Sparkle's helpers before the frameworks; no check is loosened, because `mac-check` now also refuses a helper that another team signed.
- **2026-11-16** — Assumed: the install-and-update test on a Mac moves out of the tasks to *After publishing*, because it needs the `main` run and a second test build, which come only after the publish; the branch run's Mac build is the check before it.
- **2026-11-16** — Saved for the branch run: the build and its review are done; the branch run's Mac build checks Sparkle, `Updater.swift` and the Xcode project, which this host can't build.
