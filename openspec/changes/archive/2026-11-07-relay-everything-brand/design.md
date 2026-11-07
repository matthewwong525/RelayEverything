## Context

See proposal.md, Why. Today `mobile/lib/app.dart` and `mobile/lib/share/share_main.dart` each build `ThemeData(colorSchemeSeed: Colors.indigo)`, so every color is Material's generated tint. The website sets Starlight's accent in `site/src/styles/custom.css` to blue `#3b5bdb`, and `site/src/assets/ring-mark.svg` (also `public/favicon.svg`) is a ring. The home page hero SVG in `site/src/content/docs/index.mdx` has the blue fixed in its strokes. The app is offline with sending off, so it can not fetch a font at run time.

## Goals / Non-Goals

**Goals:** one source for the brand's values in each surface; the app, share card and website using them; a new mark and icon; a check that the colors stay readable.

**Non-Goals:** changing any screen's layout, widgets or words (the next plan); the server's Relay Everything page under `app/src/apps/relay/`; the ring renders under `site/src/assets/ring/`.

## Decisions

### Brand values

Three color sets; the person picked *Emerald*, so the build ships it; the other two columns stay as the record of what was offered. Each set has the same tokens, so the theme code does not change with the pick. The board's script in `prototypes/brand/index.html` holds the same values.

| Token | Use | Emerald light / dark | Signal light / dark | Volt light / dark |
|---|---|---|---|---|
| paper | screen background | `#F7F8F4` / `#0C110F` | `#F6F8FA` / `#0A1016` | `#F7F6FB` / `#0E0C15` |
| card | cards, quiet buttons | `#FFFFFF` / `#161D1A` | `#FFFFFF` / `#131B23` | `#FFFFFF` / `#18151F` |
| line | rare dividers | `#E3E6DF` / `#26302B` | `#E1E6EB` / `#233041` | `#E4E1EE` / `#2B2638` |
| ink | text | `#121614` / `#ECF3EE` | `#0F1720` / `#EAF2F8` | `#15121F` / `#EFEDF6` |
| muted | supporting text | `#5E6660` / `#9AA8A0` | `#5A6573` / `#96A4B3` | `#625D70` / `#A29DB3` |
| accent | main action fill | `#0E7A5A` / `#4CC79A` | `#00B8D9` / `#22D3EE` | `#6D4AFF` / `#8C72FF` |
| on-accent | text on accent | `#FFFFFF` / `#06281A` | `#042B33` / `#04242B` | `#FFFFFF` / `#0E0C15` |
| accent-text | accent as text, logo on paper | `#0E7A5A` / `#4CC79A` | `#00728A` / `#5BE3F5` | `#5634E0` / `#B4A3FF` |
| accent-soft | tag background, glow | `#E1F2EA` / `#133328` | `#D9F6FC` / `#0E3442` | `#ECE7FF` / `#2A2150` |
| spark | small live moments | `#F5A524` / `#FFC24D` | `#FF6B3D` / `#FF8A5C` | `#C6F432` / `#D4FF4F` |
| on-spark | text on spark | `#121614` both | `#0F1720` both | `#15121F` both |
| danger | errors | `#C9302C` / `#FF8A80` | same | same |

Type: Inter, weights 400, 550, 650 and 700 (variable font); sizes 28 / 20 / 16 / 13; titles at -0.02em letter spacing. Corners: 12 on buttons and fields, 16 on cards. Spacing: 4, 8, 12, 16, 24, 32. The main button carries a soft shadow in the accent color (the "glow").

### The mark

A capital R on a 48 by 48 grid, 4-unit round strokes, in five takes drawn in the board's script: *Relay R* (the leg is a switch arm on a pivot, swinging toward a contact dot, with a spark), *Trace R* (straight traces with 45-degree corners and a pad at each end), *Rooted R* (three pins join into the stem), *Signal R* (two spark-colored waves off the bowl) and *Bolt R* (the leg is a spark-colored bolt). The person picked *Signal R*; the build copies its paths exactly. Strokes are `accent-text` on paper and `on-accent` on the icon; the spark parts are `spark`. The board animates spark-colored dashes along the wires; the shipped files are still.

### One theme file in the app

`mobile/lib/brand.dart` holds the tokens above as two `BrandColors` sets and builds `ThemeData` for light and dark from an explicit `ColorScheme` (not `fromSeed`), so Material's widgets pick up paper, card, ink and the accent without each screen naming a color. `app.dart` and `share_main.dart` both call it, so the two can not drift. A `ThemeExtension` carries the tokens Material has no slot for (paper vs card, muted, accent-text, accent-soft, spark, on-spark). Material slots: `surface` = paper, `surfaceContainer*` = card, `onSurface` = ink, `onSurfaceVariant` = muted, `primary` = accent, `onPrimary` = on-accent, `primaryContainer` = accent-soft, `onPrimaryContainer` = accent-text, `tertiary` = spark, `onTertiary` = on-spark, `outlineVariant` = line, `error` = danger. Card theme: no border, card color, radius 16. Filled and FAB buttons: accent with on-accent text and the accent glow. *Alternative:* `colorSchemeSeed` with the accent; rejected because the seed dulls a bright color into its own tones, which is the look you called dull.

`share_card.dart`'s `Colors.black38` scrim stays: it is a dim layer over another app, not a brand color.

### Font in the app

Inter's variable TTF and `OFL.txt` go in `mobile/assets/fonts/inter/`, declared under `fonts:` in `pubspec.yaml`. No `google_fonts` package: it fetches at run time, which breaks the offline promise. The license goes into Flutter's license page with `LicenseRegistry.addLicense`.

### Logo and icon from one source

`brand/` at the repo root holds `mark.svg` (the picked mark, `currentColor`), `logo.svg` (mark plus *Relay Everything* as outlined paths, so it needs no font), and `icon.svg` (the mark in on-accent on an accent square, light set, full bleed: each platform rounds its own corners). `brand/make-icons.mjs` writes `icon.svg` from `mark.svg`, draws it once at 1024 px with headless Chromium (ImageMagick's own SVG renderer drops paths and stroke colors), and sizes it with ImageMagick (`magick`) into every size `AppIcon.appiconset/Contents.json` lists and every Android `mipmap-*` density, plus the launch logo. It is deterministic and rerun by hand when the mark changes; the PNGs are committed because the builds read them from the platform folders. *Alternative:* `flutter_launcher_icons`; rejected because it adds a dev dependency for a job a 40-line script does, and still needs a PNG made from the SVG.

Android gets an adaptive icon too (`mipmap-anydpi-v26/ic_launcher.xml`, accent background, mark foreground) so it is not shown inside a white circle.

### Launch screen

iOS `LaunchScreen.storyboard` background changes from white to the light paper, and `LaunchImage` becomes the mark in accent-text and spark. Android `launch_background.xml` uses the same paper color and mark. Dark launch screens keep paper too: a launch screen shows for under a second, and one color is simpler than two storyboards.

### Website

`custom.css` sets Starlight's accent variables from the picked set (`--sl-color-accent` = accent-text, `-low` = accent-soft, `-high` = ink) and `--sl-font` to Inter, loaded with `@font-face` from `site/public/fonts/` (self-hosted, with `OFL.txt`). Starlight's gray scale is tinted to match the set's paper. `site/src/assets/relay-mark.svg` replaces `ring-mark.svg` as the top-bar logo; `public/favicon.svg` becomes the icon. The hero SVG's strokes use the accent variable and the spark instead of `#3b5bdb`. `ring-mark.svg` is deleted if nothing else uses it.

### The readability check

`mobile/test/brand_test.dart` computes the WCAG contrast ratio for each text-on-background pair (ink and muted on paper and card, on-accent on accent, accent-text on paper, card and accent-soft, on-spark on spark, danger on paper and card) for the shipped set, light and dark, and fails below 4.5, naming the pair. All three sets in the table pass today; the lowest pair is accent-text on accent-soft in *Emerald* light, 4.6. A `site/tests/brand.test.mjs` asserts the built site's CSS has no `#3b5bdb` and no font URL to another host.

## UX

### Use-case brief

Who: a person who keeps notes, voice notes and shared items on their phone and sends them, with health and places, to their own space for their AI. The look should feel alive, with current flowing through the R, but not loud: a deep green, and the bright spark only in small places. Context: phone, one hand, many short visits a day. This change touches no flow; it sets the look every later screen uses.

### Flow

Unchanged. Every screen keeps its layout; only colors, font, logo and icon change.

### Hierarchy

The accent goes only on the one main action of each screen (*New note* on the timeline, *Save* on compose and the share card, the main button in Settings and Connect). Today's tinted chips and outlines turn ink or muted. Where a screen today has two filled buttons, both stay as they are; the next plan picks one.

### Review

`review.html`: item 1 is the brand board (live card), item 2 the app's Before pictures with the board's section 6 as After, item 3 the icon and launch screen, item 4 the website, item 5 the rules.

### Components

No new widgets. One new theme file and one theme extension; Material's own widgets read them.

## Risks / Trade-offs

- [Material widgets that read slots we do not set show a stray tint] → set every `ColorScheme` slot explicitly and look at each screen in the device check's screenshots, light and dark.
- [Icon PNGs drift from the SVG] → the script is the only way to make them, and the wiki brand page says to rerun it.
- [Inter adds about 300 KB to the app] → accepted; one variable file covers every weight.
- [A bright accent fill has low contrast against paper as a shape] → the button is known by its ink label and glow, and every label passes 4.5 to 1; the accent never carries text on paper, accent-text does.
- [A screen sets a color in code] → only `share_card.dart`'s scrim does today; the brand page says to use theme tokens.

## Migration Plan

Ships with the next app build and website publish. Rollback is a revert: no data or route changes.
