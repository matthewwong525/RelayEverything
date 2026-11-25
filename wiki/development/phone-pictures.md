# Real pictures of a phone app screen

A screen test draws a real picture of a Relay Everything phone app screen on this computer, for your own checks. A plan does not use it: a plan writes each phone screen as a page in the phone app's look ([another app's look](../prototypes.md#another-apps-look)). It is part of [Development](README.md).

## Draw the app's own screens

A Flutter widget test draws the real screen, with sample data, to a PNG. It takes about 2 seconds and needs no phone.

1. Make a throwaway copy at the commit you check: `git worktree add --detach .scratch/<change>-pictures HEAD`, then `flutter pub get --offline` in its `mobile/`. Git never takes the copy.
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
6. Remove the copy with `git worktree remove --force .scratch/<change>-pictures` when you are done.

## What the screen test can't draw

The test draws only what Flutter draws. These parts need the [device check](device-check.md) on a Mac:

- **The iPhone's own parts**: its text menu, share sheet, keyboard, *Allow Paste?* question, and photo picker.
- **A note's words.** Since 2026-11-25 the note is a web page in a web view ([the note editor](../relay-note-editor.md)), and a widget test draws no web view. The bars around the note draw; check the words and the file cards with the editor's own Chromium tests, `npm test` in `mobile/editor-web/`.
- **Words in a Flutter part with no font name**: the test's own font draws them as blocks, and a loaded font does not replace it.

Up: [Development](README.md). Sideways: [prototypes](../prototypes.md), [the device check](device-check.md).
