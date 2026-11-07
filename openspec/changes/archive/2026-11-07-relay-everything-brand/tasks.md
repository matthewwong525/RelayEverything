## 1. Logo and icon

- [x] 1.1 Draw the picked mark in `brand/mark.svg` (`currentColor`), `brand/logo.svg` (mark plus outlined wordmark) and `brand/icon.svg` (on-accent mark on accent, full bleed), from *Signal R*'s paths in `prototypes/brand/index.html` (stem, bowl, leg, and the two waves in spark); verify each opens in a browser and matches the board.
- [x] 1.2 Write `brand/make-icons.mjs` to render `icon.svg` with `magick` into every size in `mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json`, every Android `mipmap-*` density, an Android adaptive icon (`mipmap-anydpi-v26/ic_launcher.xml` with accent background and mark foreground), and the iOS `LaunchImage` and Android launch mark; run it and verify `git status` shows only the expected PNG and XML files, and that the 1024 px icon has no alpha (App Store rule).
- [x] 1.3 Set the iOS `LaunchScreen.storyboard` background and Android `launch_background.xml` to the light paper with the mark centered; verify in the simulator build of task 2.5.

## 2. The app

- [x] 2.1 Add Inter's variable TTF and `OFL.txt` under `mobile/assets/fonts/inter/`, declare the font in `pubspec.yaml`, and register the license with `LicenseRegistry`; verify `flutter pub get` and the license page lists Inter.
- [x] 2.2 Write `mobile/lib/brand.dart`: *Emerald*'s light and dark tokens from design.md, a `ThemeExtension` for paper, card, muted, accent-text, accent-soft, spark and on-spark, and light and dark `ThemeData` with every `ColorScheme` slot set, Inter, card, button and FAB themes; use it in `app.dart` and `share/share_main.dart` in place of `colorSchemeSeed: Colors.indigo`; verify `grep -rn colorSchemeSeed mobile/lib` finds nothing.
- [x] 2.3 Show the mark beside *Relay Everything* in the timeline's app bar, from `brand/mark.svg` drawn as a small Flutter `CustomPainter` or an asset, in the accent color; verify with a widget test that finds it.
- [x] 2.4 Write `mobile/test/brand_test.dart`: the contrast ratio of each text-on-background pair in design.md, light and dark, at least 4.5, with the failing pair named; and a test that both themes use Inter. Verify `flutter test` passes, and fails when light muted is set to `#9AA39C`.
- [x] 2.5 Run `flutter analyze` and `flutter test` in `mobile/`; verify both pass and existing screen tests still pass.

## 3. The website

- [x] 3.1 Self-host Inter in `site/public/fonts/` with `OFL.txt`, set `--sl-font` and *Emerald*'s accent and grays for light and dark in `site/src/styles/custom.css`; verify `npm run build` in `site/` passes.
- [x] 3.2 Add `site/src/assets/relay-mark.svg` as the top-bar logo in `astro.config.mjs`, replace `site/public/favicon.svg` with the icon, recolor the hero SVG in `site/src/content/docs/index.mdx` from `#3b5bdb` to the accent and spark, and delete `ring-mark.svg` if nothing else uses it; verify `grep -rn 3b5bdb site/src site/public` finds nothing.
- [x] 3.3 Write `site/tests/brand.test.mjs`: the built CSS holds no `#3b5bdb` and no `@font-face` URL to another host; verify `npm test` in `site/` passes.

## 4. The brand page

- [x] 4.1 Write `wiki/brand.md`: feel, the token table, type scale, corners and spacing, how to use the logo and when to rerun `brand/make-icons.mjs`, and the four screen rules; link it from `wiki/README.md` and from the principles in `wiki/ux-principles.md`; verify the wiki link check passes.
- [x] 4.2 Add a line on the brand to the website's app page if it describes the look, else none; verify `node scripts/product-name.test.mjs` passes for any changed user-facing file.

## 5. Checks

- [x] 5.1 Run `node scripts/public-check.mjs`, `flutter analyze`, `flutter test`, and `npm test` in `site/`; verify all pass.
- [x] 5.2 `/save`, then verify the iPhone device check's timeline, new note and settings screenshots show the brand in light mode, and preview the website with `node scripts/publish-relay-site.mjs --ref HEAD --staging`; show both on the preview page, *Approved* (board section 6) beside *Built*.

## 6. Review fixes

- [x] 6.1 Fill the timeline's *Voice* tag and the *Listening* chip with spark (`colorScheme.tertiary`) and on-spark text, and the *Typed* tag with accent-soft and accent text, as board section 6 shows; verify a widget test in `mobile/test/screens_test.dart` finds each chip in its color, and `flutter analyze` and `flutter test` pass.
- [x] 6.2 Make `brand/make-icons.mjs` also write `brand/logo.svg`, `site/src/assets/relay-mark.svg`, `site/src/assets/relay-mark-dark.svg` and `site/public/favicon.svg` from `brand/mark.svg`, and say so in `wiki/brand.md`; verify a second run leaves `git status` unchanged, and a changed color reaches each file.
- [x] 6.3 Make `site/tests/brand.test.mjs` search every built `.html`, `.css` and `.svg` file for `#3b5bdb`, any case, so the hero SVG's attributes are checked; verify `npm test` in `site/` passes.
