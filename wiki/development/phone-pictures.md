# Real pictures of a phone app screen

A plan that changes a screen of the Relay Everything phone app shows real pictures of the app, not a `screen` sketch. The [prototype](../review-pages.md#the-prototype) serves only the web app, so the phone app gets its pictures from a screen test on this computer. It is part of [Development](README.md).

## Draw the app's own screens

A Flutter widget test draws the real screen, with sample data, to a PNG. It takes about 2 seconds and needs no phone.

1. Make a throwaway copy at the plan's commit: `git worktree add --detach .scratch/<change>-pictures HEAD`, then `flutter pub get --offline` in its `mobile/`. Git never takes the copy.
2. Write a test in the copy's `mobile/test/plan_pictures/`. Import `FakeRelay` and `openFolder` from `../screens_test.dart`, pump `RelayApp(relay: relay)` with sample `relay.entries`, and tap to the screen and state you want.
3. Load the real fonts first. The test font draws every letter and icon as a black block:

   ```dart
   Future<void> font(String family, String file) =>
     (FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())))).load();

   setUpAll(() async {
     await font('Inter', 'assets/fonts/inter/InterVariable.ttf');
     await font('CupertinoSystemText', 'assets/fonts/inter/InterVariable.ttf');
     await font('packages/cupertino_icons/CupertinoIcons',
       '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf');
     await font('MaterialIcons', '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
   });
   ```

4. Draw an iPhone: `debugDefaultTargetPlatformOverride = TargetPlatform.iOS`, `tester.view.physicalSize = const Size(1170, 2532)`, `tester.view.devicePixelRatio = 3`, and `WidgetsApp.debugAllowBannerOverride = false`.
5. Save each state with `await expectLater(find.byType(RelayApp), matchesGoldenFile('out/<state>.png'))`, and run `flutter test test/plan_pictures/<file>.dart --update-goldens`.
6. Copy the PNGs to the change's `pictures/` and write them in the bullet's `picture` fence: *Before* from the copy at the plan's commit, *After* from the same copy with the [prototype](../review-pages.md#the-prototype) edits made in it.
7. Remove the copy with `git worktree remove --force .scratch/<change>-pictures` when the plan is done.

## What the screen test can't draw

The test draws only what Flutter draws. These parts need the [device check](device-check.md) on a Mac:

- **The iPhone's own parts**: its text menu, share sheet, keyboard, *Allow Paste?* question, and photo picker.
- **Words in a Flutter part with no font name**, such as the words in Flutter's copy of the iPhone text menu: the test's own font draws them as blocks, and a loaded font does not replace it.

For such a part, show the *Before* picture the screen test can draw, and write `No real picture: <the part>, which only an iPhone draws; the device check takes it at /verify` under the *After* sketch. After the build, the device check's pictures become the *Built* picture on [the preview page](../review-pages.md#the-prototype).

Up: [Development](README.md). Sideways: [the review pages](../review-pages.md), [the device check](device-check.md).
