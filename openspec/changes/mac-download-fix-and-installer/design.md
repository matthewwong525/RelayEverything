# Design

## Context

See proposal.md, Why. Two facts shape the approach:

- **The black window:** `main_mac.dart` awaits `relay.load()` before `runApp`. `load()` calls `KeyVault.upgrade()`, which calls `FlutterSecureStorage.readAll`. With `MacOsOptions(usesDataProtectionKeychain: false)` (the login keychain, chosen so the app needs no provisioning profile), `readAll` asks for `kSecMatchLimitAll` with `kSecReturnData`, and the file-based keychain refuses that pair with `errSecParam` (-50). The exception escapes `main`, so no frame draws. Log from Matthew's Mac, 2026-11-16: `PlatformException(Unexpected security result code, Code: -50 …)` at `KeyVault.upgrade (connection.dart:170)`. `readWebhook` and `read` call `readAll` too.
- **The disk image:** `mobile-macos.yml` makes it with `hdiutil create -srcfolder`, so Finder opens it with its own defaults. A branch build keeps only a zip.

### Overlap with the mac-app-updates plan

The plan *mac-app-updates* (chat "The Mac app updates itself, and the website's Mac download") builds now and changes the same files: `.github/workflows/mobile-macos.yml` and `site/src/content/docs/start/install.md`. It signs Sparkle's helpers, writes an update feed, and puts the newest `.dmg` on a fixed GitHub release, `mac-updates`. This plan changes how that `.dmg` is made. The signed, notarised `.dmg` from dmgbuild SHALL be the one file that the update feed, the `mac-updates` release and the website's download all give: the same name, `Relay-Everything-Mac.dmg`, made once by `make-dmg.sh` after Sparkle's helpers and the app are signed. Whichever plan lands second takes in the other's lines in both files.

## Goals / Non-Goals

**Goals:** the signed Mac app opens on every Mac; the disk image opens as a branded, laid-out window; a pull request's build shows that window.

**Non-Goals:** a start-up error screen for other failures; a change to where the key is kept; a new installer type (`.pkg`).

## Decisions

### Read each saved name by itself, on every platform

`KeyVault` gets `_readNames(options)`, which calls `_storage.read(key: name, iOptions: options)` for each name it owns (`_names` and the two webhook names) and returns the found ones as a map. `read`, `upgrade`, `_readShared` and `readWebhook` use it in place of `readAll`. A single `SecItemCopyMatching` for one item with `kSecReturnData` is valid on both keychains.

- *Why every platform, not only the Mac:* one code path, and the vault only ever used the names it owns. iPhone and Android see the same values. Six small reads at start cost nothing a person sees.
- *Alternative:* `usesDataProtectionKeychain: true` on the Mac. Refused: it needs the `keychain-access-groups` entitlement, which needs a provisioning profile in a Developer ID app, which the mac-app plan chose to avoid.
- *Alternative:* catch the error and start signed out. Refused: a signed-in Mac would forget its key on each open.

`MemoryStorage` in `test/fakes.dart` gets `read`, and a `refuseReadAll` switch that throws `PlatformException(code: 'Unexpected security result code', message: 'Code: -50')` as the Mac does. Tests: the vault reads, upgrades and reads the webhook with `refuseReadAll` on; a `RelayController(platform: RelayPlatform.mac)` loads with it on.

### Make the disk image with dmgbuild

`dmgbuild` (Python, pinned with `pip install dmgbuild==<version>` on the runner) writes the window's `.DS_Store` itself: window size, icon size and positions, hidden toolbar and sidebar, background picture, volume icon. It needs no Finder and no AppleScript.

- *Alternative:* `create-dmg` (shell plus AppleScript to Finder). Refused: Finder automation on a headless CI runner can hang or fail without a person to allow it.

`mobile/macos/dmg/settings.py` holds the layout: window 660 by 428 (the 400-point background and Finder's 28-point title bar), icons 128, the app at (170, 188), Applications at (490, 188), `show_status_bar`, `show_tab_view`, `show_toolbar`, `show_pathbar` and `show_sidebar` off, `icon` from the built app's `Contents/Resources/AppIcon.icns`, `format = 'UDZO'`. `mobile/macos/dmg/make-dmg.sh <app> <dmg>` runs dmgbuild with it; both the branch step and the signed step call it. The signed path signs the app first, then makes the image, then signs the image, as now. `scripts/app-release.mjs mac-check` is unchanged.

### Draw the background with the brand script

`brand/make-icons.mjs` writes `mobile/macos/dmg/background.png` (660 by 400) and `background@2x.png` (1320 by 800), drawn by the same headless Chromium from an SVG: paper `#F7F8F4`; at the top, the mark in accent-text with spark waves beside the wordmark outline from `brand/logo.svg` (no font needed); a band at y 100 to 300 with 16 corners in the band green; a white arrow between the two icon spots; and *Drag Relay Everything to Applications* in muted, Inter 16, from `mobile/assets/fonts/inter/InterVariable.ttf` through `@font-face`. dmgbuild combines the PNG and its `@2x` into one multi-resolution picture.

- **Band green `#158662`.** Finder draws icon names white in dark mode and black in light mode, whatever is behind them. `#158662` gives 4.55 to 1 with white and 4.62 to 1 with black. The script throws, naming the ratio, when the band color drops below 4.5 to 1 with either. Matthew chose the band on 2026-11-16.
- *One bright thing:* the spark stays only in the mark's waves; the arrow is white, not spark.

## UX

### Use-case brief

A person downloads the Mac app from the website and opens the file. The job: put the app in Applications in one drag. Edge cases: dark mode, a Retina screen, a Mac that already has an older copy (Finder asks to replace it).

### Flow

Open the file → the window shows → drag the app onto Applications → open it from Applications → the notes window shows.

### Hierarchy

One action: the drag. The arrow and the one line of words point to it; the logo is quiet, at the top.

### Review

[review.html](review.html), What Changes items 1 and 2.

### Components

No app parts. The background reuses the brand mark, the wordmark outline and the Emerald tokens; the band green is new, only in this picture, for the label-contrast reason above.

## Risks / Trade-offs

- [Finder's real label colors are slightly softer than pure white and black] → the band is centered between them, and the apply step checks a screenshot of the window in both modes from the pull request's image.
- [dmgbuild's layout depends on Finder reading its `.DS_Store`; a new macOS could change how] → it is the common tool for this, used by many Mac apps; the window still opens with both icons if the layout is ignored.
- [Six keychain reads where one was] → none a person sees.

## Migration Plan

None. A Mac that never opened has nothing saved; the next download replaces the app.
