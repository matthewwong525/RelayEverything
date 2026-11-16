# Tasks

## 1. The Mac app opens

- [x] 1.1 In `mobile/lib/data/connection.dart`, add `KeyVault._readNames(options)` that reads each owned name with `_storage.read`, and use it in `read`, `upgrade`, `_readShared` and `readWebhook` in place of `readAll`; verify no `readAll` remains in `lib/` with `grep -rn readAll mobile/lib`.
- [x] 1.2 In `mobile/test/fakes.dart`, give `MemoryStorage` a `read` and a `refuseReadAll` switch that throws the Mac's -50 `PlatformException`; add tests that the vault reads, upgrades, and reads the webhook with it on, and that `RelayController(platform: RelayPlatform.mac).load()` finishes with a saved key; verify `flutter test` passes in `mobile/`.
- [x] 1.3 Update the key bullet in the Mac section of `mobile/README.md`: the vault reads each name by itself, because the login keychain refuses a read-all; verify the line reads right.

## 2. The install window

- [x] 2.1 In `brand/make-icons.mjs`, draw `mobile/macos/dmg/background.png` and `background@2x.png` as the design says, and throw when the band green is under 4.5 to 1 with white or black; run `node brand/make-icons.mjs` twice and verify the second run changes nothing and the picture matches the plan's drawing.
- [x] 2.2 Add `mobile/macos/dmg/settings.py` (the dmgbuild layout) and `mobile/macos/dmg/make-dmg.sh <app> <dmg>`; verify `bash -n` passes on the script and `python3 -m py_compile` on the settings.
- [x] 2.3 In `.github/workflows/mobile-macos.yml`, install a pinned dmgbuild, make the image with `make-dmg.sh` in the signed step in place of `hdiutil create`, and on a branch make and keep the unsigned image in place of the zip; verify `actionlint` passes, or the YAML parses if it is missing.
- [x] 2.4 If mac-app-updates landed first, take in its lines: make the image with `make-dmg.sh` after Sparkle's helpers and the app are signed, and give that one signed, notarised `Relay-Everything-Mac.dmg` to the update feed, the `mac-updates` release and the website; if this plan lands first, leave a note in that plan's chat. Verify `grep -n "hdiutil create" .github/workflows/mobile-macos.yml` finds nothing and the feed step reads the same `$DMG`.
- [x] 2.5 Update `wiki/brand.md` (the script also writes the install window's background; the band green and its reason), the Mac build bullets in `mobile/README.md` (a branch keeps the unsigned disk image; dmgbuild makes the window), and step 2 of the Mac section in `site/src/content/docs/start/install.md` (the window shows the app and Applications); verify `node scripts/product-name.test.mjs` passes.

## 3. Checks

- [x] 3.1 Run `node scripts/public-check.mjs` and the mobile tests; verify both pass.
- [ ] 3.2 `/save`, then download the pull request's unsigned `Relay-Everything-Mac.dmg` from its run; verify on a Mac, in light and dark mode, that the window matches the plan and that the installed app opens to its notes window, and get Matthew's screenshot if no Mac is at hand.
