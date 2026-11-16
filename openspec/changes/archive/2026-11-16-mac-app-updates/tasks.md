# Tasks

## 1. Keys and certificate

- [x] 1.1 Get the Developer ID certificate from Matthew through the private key link (`MACOS_DEVID_CERT_P12`, `MACOS_DEVID_CERT_PASSWORD`), then `gh secret set` both. Verify: `gh secret list` shows both names.
- [x] 1.2 Write `scripts/sparkle-key.mjs`: makes an Ed25519 key, writes the base64 seed as `SPARKLE_ED_PRIVATE_KEY` to the primary `.env` and the GitHub secrets, prints the public key, and refuses to replace a saved key without `--renew`. Declare `SPARKLE_ED_PRIVATE_KEY` in `.env.example`. Add `scripts/sparkle-key.test.mjs` for the refuse and the key form. Verify: the test passes; run it once and `gh secret list` shows the name.

## 2. The updater in the Mac app

- [x] 2.1 Add Sparkle 2 as a Swift package on the Runner target in `mobile/macos/Runner.xcodeproj`; add `Updater.swift` (one `SPUStandardUpdaterController`, the `allowedChannels` delegate on `RelayTestBuilds`, the `relay/updates` channel with `check`, `setTestBuilds`, `canCheck`) and register it in `MainFlutterWindow.swift`. Verify: the branch run's Mac build passes.
- [x] 2.2 `Info.plist`: `SUFeedURL`, `SUPublicEDKey` (from 1.2), `SUEnableInstallerLauncherService`, `SUEnableDownloaderService` = NO, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval` = 86400, `SUAutomaticallyUpdate` = NO. Both entitlements files: the two `mach-lookup` exceptions. Verify: the built app's `codesign -d --entitlements -` shows them (branch run log).
- [x] 2.3 Dart: `lib/mac/updates.dart` (`MacUpdates` and a fake), *Check for Updates…* after *About* in `macMenus`, a background check after the first frame in `main_mac.dart`, `SettingsRow.updates` with *Check for Updates…* and *Get test builds* on the Mac only, `Relay.testBuilds` / `setTestBuilds` in `RelayController` and `FakeRelay`, and the web `SettingsPage.listed` line. Tests in `test/mac_shell_test.dart`: the menu item and the Settings row each call `check`; the switch calls `setTestBuilds(true)` and keeps the value; the phone and the web show no *Updates*. `test/mac_imports_test.dart` still passes. Verify: `flutter test` passes.

## 3. Build, sign and feed

- [x] 3.1 `mobile-macos.yml`: sign Sparkle's `Installer.xpc`, `Downloader.xpc` (keep its entitlements), `Autoupdate` and `Updater.app` before `Sparkle.framework`, then the rest as today. `app-release.mjs mac-check`: refuse a `.dmg` whose Sparkle helpers are not signed by the Developer ID team; add a case to its test. Verify: the tests pass, and the `main` run's *Check the disk image* step passes.
- [x] 3.2 `app-release.mjs mac-feed`: read the current `appcast.xml`, sign the `.dmg` with Ed25519 from `SPARKLE_ED_PRIVATE_KEY`, add the item with its channel, keep 10 per channel, write the file. Tests: a fixed key and file give Sparkle's signature form; a release item has no channel and a test item has `beta`; an 11th item drops the oldest of its channel only; a missing feed starts a new one. Verify: `node --test scripts/app-release.test.mjs` passes.
- [x] 3.3 `mobile-ci.yml`: a `mac-feed` job after `macos-beta` and after the release job, in a `concurrency: mac-feed` group with no cancel. It makes the `mac-updates` pre-release once if missing (never latest), runs `mac-feed`, and uploads `appcast.xml` and `Relay-Everything-Mac.dmg` with `--clobber`. A `release-check` writes no feed. Verify: after the `main` run, `curl -sIL …/releases/download/mac-updates/appcast.xml` and `…/Relay-Everything-Mac.dmg` give 200.

## 4. Website and docs

- [x] 4.1 `site/src/content/docs/start/install.md`: *Download for Mac* links to `releases/download/mac-updates/Relay-Everything-Mac.dmg`; the update line says the app checks and asks. The *On a computer* page's Mac part names *Check for Updates…* and *Get test builds*. Update `site/tests/site.test.mjs` if it lists the link. Verify: `npm test` in `site/` passes, and the staging site shows it.
- [x] 4.2 `mobile/README.md` *The Mac app*: the updater, the feed, `mac-updates`, the update key and its `--renew` warning. `wiki/open-source.md` *phone builds*: the update key as a secret to keep. Verify: the wiki check passes.

## 5. Checks

- [x] 5.1 Run the Flutter tests, the script tests, `node scripts/public-check.mjs` and `scripts/product-name.test.mjs`. Verify: all pass.
- [x] 5.2 `/save`, and the branch run's Mac build passes with Sparkle inside the app. Verify: the run's *Mac* job is green.

## After publishing (not a build task)

After the `main` run: install the Mac app from *Download for Mac*, publish one more test build, turn *Get test builds* on, pick *Check for Updates…*, and install it. The app opens on the new build number with the same notes; with the switch off, the next check says it is up to date. Only a Mac can do this.
