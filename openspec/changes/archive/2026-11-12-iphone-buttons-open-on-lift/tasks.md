# Tasks

## 1. Buttons act on lift on iPhone

- [x] 1.1 In `mobile/lib/app.dart`, wrap `theme` and `darkTheme` in a helper that, on `TargetPlatform.iOS` only, sets `tooltipTheme: TooltipThemeData(triggerMode: TooltipTriggerMode.manual)`, read in `build`; verify `flutter analyze` is clean.
- [x] 1.2 In `mobile/test/screens_test.dart`, add a test: with `debugDefaultTargetPlatformOverride = TargetPlatform.iOS`, a 1-second press on `find.byTooltip('Settings')` opens Settings and shows no tooltip; a second test on Android shows the tooltip and stays on Home; verify both pass, and fail with 1.1 undone.
- [x] 1.3 Verify the whole `flutter test` suite in `mobile/` passes, including the *New note* hold to talk tests.

## 2. Guides

- [x] 2.1 In `site/src/content/docs/app/settings.md`, add one sentence after the gear line: on an iPhone, a long press on the gear opens Settings too; verify `node scripts/product-name.test.mjs` passes.
- [x] 2.2 In `wiki/development/device-check-tour.md`, rewrite *A slow Mac can turn a tap into a long press* to say the app now acts on lift on iPhone, so a slow tap on a named button works, and that *New note*'s hold still records on a slow tap; fix the last bullet's *A Maestro tap is short* to match; verify the wiki link check passes.

## 3. Check

- [x] 3.1 `/save`, then `/verify` with the device check, fixed tour only: the `settings` step passes with `tries: 1` in `tour.json`.
