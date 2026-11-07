# The Relay Everything brand

Relay Everything's look: the logo, the colors, the type and the four rules that every screen of the phone app, its share card and [the website](relay-website.md) follow. Each later screen change starts from this page; [UX principles](ux-principles.md) decide what a screen is, and this page decides how it looks.

## Feel

Alive, not loud. Clean paper and ink, one deep green for the one main action, and a small amber spark for live moments. Current flows through the R, but the screen stays calm.

## The logo

The mark is *Signal R*: a capital R on a 48 by 48 grid, in round strokes 4 units wide, with two waves off its bowl. The R is the accent text color on paper and white on the icon; the waves are the spark color.

| File | What it is | Where it goes |
|---|---|---|
| [`brand/mark.svg`](../brand/mark.svg) | The mark. The R is `currentColor`, the waves are spark. | The one source of the drawing. |
| [`brand/logo.svg`](../brand/logo.svg) | The mark and *Relay Everything* in Inter Bold, as outlines, so it needs no font. It follows the reader's light or dark setting. The script below redraws its mark and keeps its wordmark. | Documents, slides, a README. |
| [`brand/icon.svg`](../brand/icon.svg) | The mark in white on the accent, full bleed. Each platform rounds its own corners. | Made by the script below. |

- **Rerun the icon script** after a change to `brand/mark.svg` or to a brand color: `node brand/make-icons.mjs`, then commit what it writes. It writes `brand/icon.svg`, `brand/logo.svg`, the website's two top-bar marks and its favicon, every iPhone icon size, every Android density, the Android adaptive icon and both launch marks. Headless Chromium draws, because ImageMagick's own SVG renderer drops paths: set `RELAY_CHROME` if it finds no Chromium. Never edit a file it writes by hand: the next run replaces it. A second run changes nothing.
- **The app draws the mark in code** (`RelayMark` in [`mobile/lib/brand.dart`](../mobile/lib/brand.dart)), with the same paths. A change to the mark changes both.
- **The website uses** `site/src/assets/relay-mark.svg` (light) and `relay-mark-dark.svg` in the top bar, and the icon with round corners as `site/public/favicon.svg`. The script writes all three.
- **The icon stays still.** Only the sync dot moves, and only while it says *Syncing*: [words with every color](#rules-for-every-screen).
- **The ring circle is not the logo.** It shows only on the ring's own pages.

## Colors

The *Emerald* set. Each token has a light and a dark value; the app and the website follow the phone's or the browser's setting.

| Token | Use | Light | Dark |
|---|---|---|---|
| paper | screen background | `#F7F8F4` | `#0C110F` |
| card | cards, quiet buttons | `#FFFFFF` | `#161D1A` |
| line | rare dividers | `#E3E6DF` | `#26302B` |
| ink | text | `#121614` | `#ECF3EE` |
| muted | supporting text | `#5E6660` | `#9AA8A0` |
| accent | the main action's fill | `#0E7A5A` | `#4CC79A` |
| on-accent | text on accent | `#FFFFFF` | `#06281A` |
| accent-text | accent as text, logo on paper | `#0E7A5A` | `#4CC79A` |
| accent-soft | tag background, glow | `#E1F2EA` | `#133328` |
| spark | small live moments | `#F5A524` | `#FFC24D` |
| on-spark | text on spark | `#121614` | `#121614` |
| danger | errors | `#C9302C` | `#FF8A80` |

- **Each color has one home per surface.** The app: [`mobile/lib/brand.dart`](../mobile/lib/brand.dart), as `BrandColors` and the theme built from it. The iPhone share sheet: [`mobile/ios/ShareExtension/Brand.swift`](../mobile/ios/ShareExtension/Brand.swift), because it runs outside Flutter. The website: `site/src/styles/custom.css`. The icons: the constants at the top of `brand/make-icons.mjs`. Change all four together, and this table. `mobile/test/brand_test.dart` fails, and names the token, when a value in `Brand.swift` is not the same as in `BrandColors`.
- **A screen reads the theme, never a color in code.** Use `Theme.of(context).colorScheme` or `brandOf(context)`. A fixed color does not follow dark mode. The share card's dim layer over another app is the one exception.
- **Every text color stays at 4.5 to 1 or more** on each background it sits on, light and dark. `mobile/test/brand_test.dart` checks each pair and names the one that fails.
- **Material's slots map to the tokens:** surface is paper, every surface container is card, primary is accent, primary container is accent-soft, tertiary is spark, secondary is ink. Selected chips and segments stay ink on a quiet fill, because the accent is for the one main action.

## Type

Inter, one variable font, inside the app, inside the iPhone share sheet and served by the website: no network call, no outside font host. The SIL Open Font License sits beside each copy (`mobile/assets/fonts/inter/OFL.txt`, `site/public/fonts/OFL.txt`), and the app's licenses page lists it. The iPhone share sheet runs outside the app, so its build takes in the app's font file and license as its own resources, and its `Info.plist` lists the font under `UIAppFonts`.

| Role | Size | Weight |
|---|---|---|
| Title | 28 | 700, letter spacing -0.02em |
| Heading | 20 | 650, letter spacing -0.02em |
| Body | 16 | 400 |
| Small | 13 | 400 |

## Corners and spacing

- **Corners:** 12 on buttons and fields, 16 on cards. *New note* is a round button, 52 px, with an icon and no words; its accessibility label is *New note*.
- **Spacing:** 4, 8, 12, 16, 24, 32.
- **The glow:** the one main action carries a soft shadow in the accent color (`AccentGlow` in the app).

## Rules for every screen

| Rule | What it means |
|---|---|
| One bright thing | The accent marks the one main action on a screen. The spark is for small live moments: the *Voice* tag, *Listening* and *New note* while it records fill with spark, with on-spark text. A *Typed* tag is accent text on accent-soft. Everything else is ink or muted. |
| Cards, no borders | A card is a lighter shape on paper. No box inside a box. |
| Words with every color | A state says its name: *Synced*, *Waiting*, *Off*. Never color alone. The sync dot sits beside its word: still accent for *Synced*, spark that pulses for *Syncing*, a hollow ring for *2 waiting* and *Offline*, danger for *Key refused*, and no dot for *On this phone*. With reduced motion on the phone, the dot stays still. |
| Soft corners | 12 px on buttons and fields, 16 px on cards. |

These rules apply the [UX principles](ux-principles.md#principles) *one primary action*, *fewer borders* and *never rely on color alone* to Relay Everything.
