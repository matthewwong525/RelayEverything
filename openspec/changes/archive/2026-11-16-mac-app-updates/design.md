# Design

## Context

The Mac app (`lib/main_mac.dart`, `mobile/macos/`) is a sandboxed, Developer ID-signed Flutter app. Its Runner gets Flutter plugins through Swift Package Manager (`FlutterGeneratedPluginSwiftPackage`) and has no Podfile. [`mobile-macos.yml`](../../../.github/workflows/mobile-macos.yml) signs each framework, then the app, notarizes and staples `Relay-Everything-Mac.dmg`. Then [`mobile-ci.yml`](../../../.github/workflows/mobile-ci.yml) puts it on the build's GitHub release: a pre-release `mobile-v<version>+<build>` for `main`, and the `v<x.y.z>` release for a tag. Every GitHub release is a pre-release today, so `releases/latest/download/Relay-Everything-Mac.dmg` gives 404. Also, `MACOS_DEVID_CERT_P12` and `MACOS_DEVID_CERT_PASSWORD` are missing, so `main` makes no Mac file at all. `CFBundleVersion` is the run's build number, which goes up with each run on `main` and each release, so Sparkle can compare builds by it.

## Goals / Non-Goals

**Goals:** a signed update path that keeps App Sandbox; two channels in one feed; one fixed address for the feed and for the newest `.dmg`; a feed writer that is a tested script, not a hand step.

**Non-Goals:** delta updates; a Sparkle UI of our own; the downloader XPC service (the app already has `network.client`); a separate appcast per channel.

## Decisions

### Sparkle 2, through Swift Package Manager in the Runner

Add `https://github.com/sparkle-project/Sparkle` (2.x, up to next major) as an `XCRemoteSwiftPackageReference` on the Runner target. A new `mobile/macos/Runner/Updater.swift` holds one `SPUStandardUpdaterController` and is the `SPUUpdaterDelegate`. A `FlutterMethodChannel` named `relay/updates` gives Dart three calls: `check` (a user-started check, with Sparkle's standard window), `setTestBuilds(bool)`, and `canCheck`.

- *Alternative: the `auto_updater` pub package.* It wraps Sparkle through CocoaPods, and this Runner has no Podfile. Its sandbox support is not clear. Our own wrapper is about 40 lines.
- *Alternative: our own updater.* It needs an installer that runs outside the sandbox, signature checks, and a window. Sparkle has all of these.

### App Sandbox

Sparkle 2 installs from a sandboxed app through its installer XPC service:

- `Info.plist`: `SUEnableInstallerLauncherService` = `YES`, `SUEnableDownloaderService` = `NO`, `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` = `YES`, `SUScheduledCheckInterval` = `86400`, `SUAutomaticallyUpdate` = `NO`.
- `Release.entitlements` and `DebugProfile.entitlements`: `com.apple.security.temporary-exception.mach-lookup.global-name` with `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`.
- On each launch, after the window shows, the app calls `checkForUpdatesInBackground()`. Sparkle's own schedule checks once a day after that.

### Two channels in one feed

The feed is one Sparkle appcast. A release item has no channel. A test-build item has `<sparkle:channel>beta</sparkle:channel>`. The delegate's `allowedChannels(for:)` returns `["beta"]` when the setting is on, else none. The setting is a `UserDefaults` bool, `RelayTestBuilds`, so Swift reads it with no call from Dart at launch. Dart writes it through `setTestBuilds`, then calls `resetUpdateCycle()`. Sparkle never offers a lower `sparkle:version`, so when the switch goes off, the app stays on its test build until a release with a higher build number comes.

### One fixed release, `mac-updates`

A pre-release with tag `mac-updates`, made once by the feed job if it is missing. It is never `--latest`. Each signed build replaces two files on it with `gh release upload --clobber`:

- `appcast.xml`, at `https://github.com/matthewwong525/RelayEverything/releases/download/mac-updates/appcast.xml`: this is `SUFeedURL`.
- `Relay-Everything-Mac.dmg`: the newest signed build, test or release. The website's *Download for Mac* links here.

Each item's enclosure points at the `.dmg` on that build's own release (`mobile-v…` or `v…`), so an older item stays valid when the fixed `.dmg` changes. GitHub's download address redirects to its file host. Sparkle follows the redirect.

- *Alternative: the feed on relayeverything.com.* The site publishes by hand, after the change merges, and the Mac build ends later. The feed would be late or missing.
- *Alternative: `releases/latest`.* It gives only full releases, and none exists with a Mac file yet.

### The feed writer: `scripts/app-release.mjs mac-feed`

A new subcommand of the existing release script, so the `version`, `mac-check` and `mark` steps stay in one place. Inputs: `--file` (the `.dmg`), `--version`, `--build`, `--tag` (the build's own release), `--channel release|beta`, and `--notes` (a file). It:

1. Reads the current `appcast.xml` from `mac-updates`. It is missing on the first run.
2. Signs the `.dmg` with Ed25519 through `node:crypto`, from `SPARKLE_ED_PRIVATE_KEY`: the base64 32-byte seed that Sparkle's `generate_keys -x` writes. It adds an item with `sparkle:version` = build, `sparkle:shortVersionString` = version, `sparkle:minimumSystemVersion` from the app, the enclosure's `url`, `length` and `sparkle:edSignature`, and the channel.
3. Keeps the newest 10 items of each channel and writes the file.

`node:crypto` needs no Sparkle tool on the Linux runner. A test checks the signature against Sparkle's own form with a fixed key and file.

The CI job `mac-feed` runs after `macos-beta` (beta) and after the release job (release). It runs in a `concurrency: mac-feed` group with no cancel, so two runs never write the feed at the same time. A `release-check` run writes no feed.

### The update key: `scripts/sparkle-key.mjs`

It makes an Ed25519 key with `node:crypto`. It writes the private seed as `SPARKLE_ED_PRIVATE_KEY` to the primary `.env` and the GitHub secrets, and prints the public key. The public key goes in `Info.plist`, where it is public. The script refuses to replace a saved key unless it gets `--renew`: a new key stops every installed app from taking updates.

### Signing Sparkle inside the app

The workflow's `find … -name '*.framework'` signs `Sparkle.framework` as a whole, but its helpers need their own signature first, inside-out, with the hardened runtime:

1. `Sparkle.framework/Versions/B/XPCServices/Installer.xpc`
2. `Sparkle.framework/Versions/B/XPCServices/Downloader.xpc`. It is in the framework even when the app does not use it. Sign it with its own entitlements (`--preserve-metadata=entitlements`).
3. `Sparkle.framework/Versions/B/Autoupdate`
4. `Sparkle.framework/Versions/B/Updater.app`
5. `Sparkle.framework`, then the other frameworks, then the app, as today.

`app-release.mjs mac-check` also checks with `codesign --verify --deep --strict` that each of the four helpers is signed with the Developer ID team.

### Dart side

- `lib/mac/updates.dart`: `MacUpdates`, a thin wrapper on the channel, with a fake for tests. `main_mac.dart` makes it and gives it to `MacApp`.
- `macMenus` gets *Check for Updates…* after the *About* item, in its own group, as Mac apps do.
- `SettingsRow.updates('Updates', only: {RelayPlatform.mac})`, before `version`. It has a `ListTile` *Check for Updates…* and a `SwitchListTile` *Get test builds*. The web `SettingsPage.listed` switch adds `SettingsRow.updates` to its `throw` line.
- `Relay` gets `testBuilds` and `setTestBuilds(bool)`. `RelayController` keeps the value in Settings and calls `MacUpdates.setTestBuilds`. `FakeRelay` records it.

## UX

### Use-case brief

Matthew, and later anyone with the Mac app, wants the newest version with no trip to the website. Edge cases: no network (Sparkle stays quiet on a background check, and shows its error only on a user-started check); already up to date (Sparkle's *You're up to date* window); the switch goes off while on a test build (no downgrade).

### Flow

App opens → background check → Sparkle's window if newer → *Install Update* → relaunch. Or: menu or Settings → *Check for Updates…* → Sparkle's window.

### Hierarchy

Settings: the new *Updates* part sits between *Appearance* and the version line, so the version and its update control are side by side. The menu item uses Mac conventions: the app menu, after *About*.

### Review

[review.html](review.html), What Changes item 2: the Settings picture.

### Components

Existing `Group`, `ListTile` and `SwitchListTile`, as the Location page's switch uses them. The update window is Sparkle's standard window, not a Flutter screen.

## Risks / Trade-offs

- [A lost or leaked update key] → A lost key means every installed app must be updated by hand once. Keep it in `.env` and the GitHub secrets, and never in the repository. `public-check.mjs` already refuses a key file.
- [The certificate needs the account holder] → *What the build needs* gives the steps. Until then, no Mac file, no feed, no update. The app with an empty feed address does not exist, because no build is made.
- [A sandbox entitlement Apple's check refuses] → The `mach-lookup` temporary exception is allowed outside the Mac App Store. Apple's check in `release-check` shows a refusal before a release.
- [The first installed app has no updater] → People with no Mac app have nothing to lose: no signed Mac app was published. The first signed build already has the updater.
- [The *note-toolbar-tables* plan also changes `macMenus` (a *Format* menu) and `test/mac_shell_test.dart`] → Whichever change lands second takes in the other's menu lines and tests when it updates from `main`.
- [GitHub pre-release clutter] → `mac-updates` is one more pre-release, made once. Its name says what it is.

## Migration Plan

1. Matthew makes the Developer ID certificate on a Mac: *Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority…*, saved to disk; upload it on Apple's *Developer ID Application* page (G2 Sub-CA); download and double-click the certificate; export it from *Keychain Access* as a `.p12` with a password. He sends `base64 -i <file>.p12` and the password through the private key link, and `gh secret set` saves both.
2. Run `node scripts/sparkle-key.mjs`, and put the printed public key in `Info.plist`.
3. Publish. The `main` run signs the app, makes `mac-updates`, and writes the first feed item (`beta`).
4. Rollback: remove the `mac-feed` job. Installed apps then see no new item and stay as they are.
