# Tasks

## 1. The Mac platform in the app

- [x] 1.1 Add `RelayPlatform.mac` and `Relay.desktop` in `mobile/lib/relay.dart`; give `RelayController` a `platform` argument (`phone` by default); switch each `relay.web` that means *a computer* to `relay.desktop` (record button, page keys, magnifier, attach menu, *Find in Note*), keep the browser-only ones; test in `mobile/test/screens_test.dart` that a `mac` controller shows no record button and keeps the page keys, and that phone and web behave as before (`flutter test`)
- [x] 1.2 Name the device `Mac` on macOS in `controller.dart`'s sign-in, and keep the key in the login keychain (`MacOsOptions(useDataProtectionKeyChain: false)`, no shared group) in `lib/data/connection.dart`; test the name and the options in `mobile/test/controller_test.dart`
- [x] 1.3 Make `WebShell.client` optional: with no client, *Connect your AI*, *Email notes* and *Settings* show the phone's screens over `Relay.connections` in the right part, and the left bar has no Location, Health, Calendar or Photos on `mac`; test the three layouts at 1,200, 800 and 500 px over a fake `mac` controller, the left bar's rows, and *Saved chats* opening the page, in a new `mobile/test/mac_shell_test.dart`; keep `web_shell_test.dart` green

## 2. The Mac entry, menus and drops

- [x] 2.1 Run `flutter create --platforms=macos .` in `mobile/`, then set the bundle id `com.matthewwong525.relayApp.mac`, the product name *Relay Everything*, the brand icon set, App Sandbox with network client and user-selected files, and hardened runtime in `mobile/macos/`; check `flutter analyze` and that `mobile/macos/Runner/*.entitlements` hold only those two keys
- [x] 2.2 Write `mobile/lib/main_mac.dart` and `MacApp` (brand theme, `PlatformMenuBar` with *New Note* ⌘N, *Find* ⌘F, *Bold* ⌘B, *Italic* ⌘I, *Settings…* ⌘,, each calling the shell's existing intent), a file opener on `url_launcher`, and no voice parts; a phone's voice note shows its words; test the menu items call the same intents as the keys in `mobile/test/mac_shell_test.dart`
- [x] 2.3 Use the shared note editor's paste as it is, with no Mac paste code (the paste-keeps-formatting change fixes it for every platform). Add `desktop_drop` and feed its drops to `WebShell.drops` as `NewFile`s; test that a drop adds a file to the open note and that a 26 MB file shows the existing *too big* words, with a fake drop stream
- [x] 2.4 Add `mobile/test/mac_imports_test.dart`: it fails when `lib/main_mac.dart` reaches `health`, `whisper_cpp_flutter_plus`, `device_calendar_plus`, `open_filex`, `lib/sync/health.dart`, `lib/sync/location.dart`, `lib/sync/background.dart` or `lib/voice/transcriber.dart`; see it fail once with a planted import, then pass
- [x] 2.5 Add *The Mac app* to `mobile/README.md` as a new section of its own, changing no other section (the app-store-listing change adds its own section there): what it is, `flutter run -d macos -t lib/main_mac.dart`, what it leaves out, and how it is built and signed

## 3. Signing, builds and releases

- [x] 3.1 Add `--mac` to `scripts/ios-signing-cert.mjs`: ask Apple for a `DEVELOPER_ID_APPLICATION` certificate and save `MACOS_DEVID_CERT_P12` and `MACOS_DEVID_CERT_PASSWORD` to `.env` and the GitHub secrets, or print the hand-made link and exit 1 on Apple's refusal; add both names, values blank, to `.env.example`; test the kind, the saved names and the refusal with a fake API in the script's test; run it once for real and report its result (ran 2026-11-15: `result=refused`, Apple lets only the Account Holder make one; the person makes it by hand)
- [x] 3.2 Write `.github/workflows/mobile-macos.yml` as its own job, and call it from `mobile-ci.yml` with one new job entry beside the iPhone build, changing no existing job or release step: on a branch, an unsigned build zipped as a run artifact; on `main` and a release, sign with hardened runtime, notarize with the App Store Connect key, staple, and make `Relay-Everything-Mac.dmg`; a missing secret skips signing on a branch and fails a release; before the edit, take the newest `main`, so a landed app-store-listing change is kept; check with `node scripts/public-check.mjs` and the workflow tests in `scripts/` that cover `mobile-ci.yml`
- [x] 3.3 Add the `.dmg` to the beta pre-release and to the `v` release with its own upload step after the step where `scripts/app-release.mjs` adds the Android `.apk`, leaving the store-page and review steps as they are, refusing an unsigned or unstapled file; test the file list and the refusal in its test

## 4. The website

- [x] 4.1 Add `## Mac` to `site/src/content/docs/start/install.md` (*Download for Mac*, the newest release's `Relay-Everything-Mac.dmg`, drag to Applications, sign in from Settings) and *The Mac app* to `site/src/content/docs/app/on-a-computer.md` (notes kept and offline, which folders it leaves out, no voice parts; a phone's voice note shows its words); check `node scripts/product-name.test.mjs` and the site's tests in `site/`

## 5. Checks

- [x] 5.1 Run `flutter analyze` and `flutter test` in `mobile/`, `node scripts/public-check.mjs`, and `node scripts/product-name.test.mjs`; all pass
- [ ] 5.2 `/save`, then see the pull request's Mac build pass on GitHub and download its unsigned app from the run

## After publishing

After the first build on `main`, the person opens the signed `.dmg` from the beta release on their Mac and reports what they see: it opens with no warning, notes work with Wi-Fi off, sign-in connects, and a note reaches the phone. The site is published with `node scripts/publish-relay-site.mjs`, as every publish does.
