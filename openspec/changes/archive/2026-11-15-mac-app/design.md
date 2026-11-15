# Design

## Context

The phone app and the computer page are one Flutter app (`mobile/`). Both run on one base, `Relay` (`lib/relay.dart`):

- `RelayController` (`lib/controller.dart`) is the phone's. It keeps notes in a local drift database (`lib/data/store.dart`), syncs them with a phone-reach key (`lib/data/note_sync.dart`, `outbox.dart`), and signs in with `flutter_web_auth_2` at `sign-in/phone` (`controller.dart` `_webAuth`). Its sources for background work, share, calendar, photos, health and places are passed in by `main.dart`, so each can be left out.
- `WebRelay` (`lib/web/web_relay.dart`) is the browser's. It keeps nothing and reads the space through `SpaceClient` with the page's cookie.
- `WebShell` (`lib/web/shell.dart`) draws the three-, two- and one-part layouts over any `Relay`, but needs a `SpaceClient` for *Connect your AI*, *Email notes*, saved chats, the connection pages and the settings dialog.
- Screens tell phone from computer with `relay.web` (`RelayPlatform { phone, web }`): it hides record, uses page keys, and so on.

Plugins with no macOS code: `health`, `whisper_cpp_flutter_plus`, `device_calendar_plus`, `open_filex`. Their Dart imports compile on macOS; a call throws `MissingPluginException`. `workmanager`, `photo_manager`, `geolocator`, `record`, `just_audio`, `flutter_secure_storage`, `flutter_web_auth_2`, `drift_flutter`, `file_picker`, `url_launcher`, `share_plus` and `package_info_plus` have macOS code.

This Linux computer has no Xcode: the Mac app compiles first on a GitHub macOS runner, as the iPhone build does (`.github/workflows/mobile-ios.yml`). The signing script `scripts/ios-signing-cert.mjs` already asks Apple's API for a certificate with the App Store Connect key.

## Goals / Non-Goals

**Goals:** a `macos/` runner and a `lib/main_mac.dart` entry; `RelayController` under `WebShell` with no `SpaceClient`; Mac menus, file drops and file opening; a signed, notarized universal `.dmg` on GitHub releases; the website's download.

**Non-Goals:** a new server route or key reach; the Mac in the CI device check; a Mac screen-picture test run on a real Mac; App Sandbox file access beyond files the person picks or drops.

## Decisions

- **One more platform, two getters.** `RelayPlatform { phone, web, mac }`. Add `bool get desktop => platform != RelayPlatform.phone` and keep `web`. Each current `relay.web` check that means *a computer* (page keys, no record button, no magnifier, the attach menu, *Find in Note*) becomes `relay.desktop`; each that means *the browser* (the browser's file words, *Not loaded*) stays `relay.web`. `RelayController` takes `platform` in its constructor, `phone` by default. Alternative: a second controller for the Mac; rejected, it would copy the sync and store code.
- **Entry `lib/main_mac.dart`**, built with `flutter build macos -t lib/main_mac.dart`. It builds `RelayController(platform: RelayPlatform.mac)` with `native`, `share`, `calendar`, `photos`, health and places sources all null, `folder: getApplicationSupportDirectory`, `opener` from `url_launcher` (`launchUrl(Uri.file(path))` for a file, in place of `open_filex`), and `voice` null: a voice note from a phone shows its words, because the recording stays on the phone, and the Mac records none. It runs `MacApp`: the brand theme, `PlatformMenuBar`, and `WebShell`. A test (`test/mac_imports_test.dart`, like `web_imports_test.dart`) fails when `main_mac.dart` reaches `health`, `whisper_cpp_flutter_plus`, `device_calendar_plus`, `open_filex`, `lib/sync/health.dart`, `lib/sync/location.dart`, `lib/sync/background.dart` or `lib/voice/transcriber.dart`.
- **The shell's page parts behind one seam.** `WebShell.client` becomes `SpaceClient?`. With a client, the shell shows the web parts as today. With none, it shows the phone's own screens over `Relay.connections`: `screens/connect_ai.dart` for *Connect your AI* (saved chats open the page, as on the phone), `screens/email_notes.dart` for *Email notes*, and the phone's `SettingsScreen` and Account page, pushed in the right part from *Settings*, for sign-in, appearance, webhooks and devices. The left bar drops Location, Health, Calendar and Photos when `relay.platform == RelayPlatform.mac`. Alternative: a new Mac shell; rejected, the layouts are the hard part and already tested.
- **Sign-in.** `controller.dart` names the device `Mac` on macOS (`Platform.isMacOS`), by the existing `signInUrl(..., name)` call. `flutter_web_auth_2` on macOS uses `ASWebAuthenticationSession` with the `relayeverything` callback scheme the server already answers. No server change: the key's reach is `phone`.
- **Keychain.** `flutter_secure_storage` with `MacOsOptions(useDataProtectionKeyChain: false)`: the login keychain needs no `keychain-access-groups` entitlement, so the app needs no provisioning profile. `Connection`'s shared-group flag stays false on macOS.
- **Background sync.** No `workmanager` on the Mac: the app syncs while it is open, on start, on each change, on network back (`connectivity_plus`), and every 5 minutes while open, by the controller's existing timer. A note made while closed does not exist, so nothing waits on a closed app.
- **Menus.** `PlatformMenuBar` with the app menu (*About*, *Settings…* ⌘,, *Quit*), *File* (*New Note* ⌘N), *Edit* (the system's Undo, Cut, Copy, Paste, Select All, then *Find* ⌘F), *Format* (*Bold* ⌘B, *Italic* ⌘I), and *Window*. Each item calls the shell's existing intent for that shortcut, so a menu and a key do the same thing.
- **File drops.** `desktop_drop` (macOS, MIT) feeds `WebShell.drops` as `NewFile`s, the stream the browser build already uses. A file over the 25 MB limit gets the existing *too big* words.
- **Entitlements.** App Sandbox on, with `com.apple.security.network.client` and `com.apple.security.files.user-selected.read-write`; hardened runtime on for notarization. Bundle id `com.matthewwong525.relayApp.mac`, product name *Relay Everything*, the brand icon in `macos/Runner/Assets.xcassets`, minimum macOS 11, as Flutter's default.
- **Signing and Apple's check.** `scripts/ios-signing-cert.mjs --mac` asks Apple for a `DEVELOPER_ID_APPLICATION` certificate, as it does for `DISTRIBUTION`, and writes `MACOS_DEVID_CERT_P12` and `MACOS_DEVID_CERT_PASSWORD` to `.env` and the GitHub secrets. On Apple's refusal for the key's role it prints the link to make it by hand and exits 1. Signing runs `codesign --options runtime --timestamp` with that certificate; `xcrun notarytool submit --wait` with the App Store Connect key; `xcrun stapler staple` on the `.dmg`. Alternative: fastlane for the Mac; rejected, three commands do it, and the Mac build needs no profile.
- **Workflow.** A separate job, so it joins cleanly with the app-store-listing change, which also changes the `v` release: a new reusable `.github/workflows/mobile-macos.yml` (`macos-latest`): `flutter build macos -t lib/main_mac.dart --release --build-name --build-number` from `mobile-ci.yml`'s plan, universal by Flutter's default. On a branch: unsigned, the `.app` zipped as a run artifact, no upload anywhere. On `main` and a release: signed, notarized and stapled `Relay-Everything-Mac.dmg` (by `hdiutil create`), added to the run's GitHub release by the step that adds the Android `.apk`. A missing secret skips signing on a branch and fails a release, as the iPhone build does.
- **Website.** `site/src/content/docs/start/install.md` gets `## Mac`: *Download for Mac* at `https://github.com/matthewwong525/RelayEverything/releases/latest/download/Relay-Everything-Mac.dmg`, drag to Applications, sign in from Settings. `site/src/content/docs/app/on-a-computer.md` gets a short *The Mac app* part linking there and saying what differs: notes kept and offline, no Location, Health, Calendar or Photos folders. `scripts/product-name.test.mjs` already reads all of `site/src/content`.

## UX

### Use-case brief

The person who uses Relay Everything on the phone, at a desk on a Mac: they write and read notes many times a day, often with the Mac offline or on bad Wi-Fi (a train, a café). Done: a note written on the Mac is on the phone soon after, and nothing is lost. Edge cases: signed out (Mac-only notes), a Mac signed out from the phone, a file drop over 25 MB, a window made narrow.

### Flow

Open from the Dock → the newest note opens in the right part → ⌘N or the compose button → type → it saves on the Mac at once and syncs when online. First run: *Settings* → *Sign in to Relay Everything* → Apple's sheet → *Connect* → notes sync both ways.

### Hierarchy

One primary action a screen, as on the computer page: the round compose button in the notes part. Settings' primary action is *Sign in to Relay Everything* while signed out.

### Review

[review.html](review.html): the What Changes item *A Relay Everything app for the Mac* shows today's computer page, the closest real result, and the sketch of the Mac window.

### Components

The Mac uses the shared note editor as it is, paste included: the paste-keeps-formatting change fixes paste there for every platform, so the Mac gets no paste code of its own.

Existing: `WebShell` and its three layouts, `Timeline`, `NoteEditor`, `RoundButton`, the phone's `SettingsScreen`, Account page, `connect_ai.dart` and `email_notes.dart` screens, `brand.dart`. New: `MacApp` (theme, `PlatformMenuBar`, shell), because the browser's `WebApp` holds cookie sign-in states the Mac does not have.

## Risks / Trade-offs

- [Apple lets only the Account Holder make a Developer ID certificate] → the script says so with the link; the person makes it once; it lasts five years.
- [A plugin with macOS code still needs a permission or entitlement at start, such as `photo_manager` or `geolocator`] → `main_mac.dart` never calls them, and the imports test keeps their sources out; the first Mac CI build and a first run on the person's Mac confirm it.
- [`flutter_quill` or the editor's keys act differently on macOS than on Chrome] → the shell's shortcut tests run with `TargetPlatform.macOS` too.
- [No self-update: a person keeps an old version] → Settings shows the version; the website always links the newest.
- [The Mac shows under *Phones* on the Account page] → its name is *Mac*; a *Computers* heading can come later.

## Migration Plan

New app; no data moves. The first signed `.dmg` comes with the first build on `main` after this ships, on its beta release; the website's link works from the next `v` release. Rollback: delete the `.dmg` from the release; Mac keys can be signed out like phone keys.
