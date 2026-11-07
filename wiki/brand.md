# The Relay Everything brand

Relay Everything's look: the logo, the colors, the type and the four rules that every screen of the phone app, its share card and [the website](relay-website.md) follow. Each later screen change starts from this page; [UX principles](ux-principles.md) decide what a screen is, and this page decides how it looks.

## Feel

Alive, not loud. Clean paper and ink, one deep green for the one main action, and a small amber spark for live moments. Current flows through the R, but the screen stays calm.

## The logo

The mark is *Signal R*: a capital R on a 48 by 48 grid, in round strokes 4 units wide, with two waves off its bowl. The R is the accent text color on paper and white on the icon; the waves are the spark color.

| File | What it is | Where it goes |
|---|---|---|
| [`brand/mark.svg`](../brand/mark.svg) | The mark. The R is `currentColor`, the waves are spark. | The one source of the drawing. |
| [`brand/logo.svg`](../brand/logo.svg) | The mark and *Relay Everything* in Inter Bold, as outlines, so it needs no font. It follows the reader's light or dark setting. | Documents, slides, a README. |
| [`brand/icon.svg`](../brand/icon.svg) | The mark in white on the accent, full bleed. Each platform rounds its own corners. | Made by the script below. |

- **Rerun the icon script** after a change to `brand/mark.svg` or to the accent: `node brand/make-icons.mjs`, then commit what it writes. It writes `brand/icon.svg`, every iPhone icon size, every Android density, the Android adaptive icon and both launch marks. Headless Chromium draws, because ImageMagick's own SVG renderer drops paths: set `RELAY_CHROME` if it finds no Chromium. Never edit an icon PNG by hand: the next run replaces it.
- **The app draws the mark in code** (`RelayMark` in [`mobile/lib/brand.dart`](../mobile/lib/brand.dart)), with the same paths. A change to the mark changes both.
- **The website uses** `site/src/assets/relay-mark.svg` (light) and `relay-mark-dark.svg` in the top bar, and the icon as `site/public/favicon.svg`.
- **The icon stays still.** A moving pulse is for a later *Syncing* state, not the icon.
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

- **Each color has one home per surface.** The app: [`mobile/lib/brand.dart`](../mobile/lib/brand.dart), as `BrandColors` and the theme built from it. The website: `site/src/styles/custom.css`. The icons: the constants at the top of `brand/make-icons.mjs`. Change all three together, and this table.
- **A screen reads the theme, never a color in code.** Use `Theme.of(context).colorScheme` or `brandOf(context)`. A fixed color does not follow dark mode. The share card's dim layer over another app is the one exception.
- **Every text color stays at 4.5 to 1 or more** on each background it sits on, light and dark. `mobile/test/brand_test.dart` checks each pair and names the one that fails.
- **Material's slots map to the tokens:** surface is paper, every surface container is card, primary is accent, primary container is accent-soft, tertiary is spark, secondary is ink. Selected chips and segments stay ink on a quiet fill, because the accent is for the one main action.

## Type

Inter, one variable font, inside the app and served by the website: no network call, no outside font host. The SIL Open Font License sits beside each copy (`mobile/assets/fonts/inter/OFL.txt`, `site/public/fonts/OFL.txt`), and the app's licenses page lists it.

| Role | Size | Weight |
|---|---|---|
| Title | 28 | 700, letter spacing -0.02em |
| Heading | 20 | 650, letter spacing -0.02em |
| Body | 16 | 400 |
| Small | 13 | 400 |

Material's 14-pixel body and label sizes stay until the screens are cleaned up, so no screen moves.

## Corners and spacing

- **Corners:** 12 on buttons and fields, 16 on cards. The floating *New note* button is a pill.
- **Spacing:** 4, 8, 12, 16, 24, 32.
- **The glow:** the one main action carries a soft shadow in the accent color (`AccentGlow` in the app).

## Rules for every screen

| Rule | What it means |
|---|---|
| One bright thing | The accent marks the one main action on a screen. The spark is for small live moments, such as recording. Everything else is ink or muted. |
| Cards, no borders | A card is a lighter shape on paper. No box inside a box. |
| Words with every color | A state says its name: *Synced*, *Waiting*, *Off*. Never color alone. |
| Soft corners | 12 px on buttons and fields, 16 px on cards. |

These rules apply the [UX principles](ux-principles.md#principles) *one primary action*, *fewer borders* and *never rely on color alone* to Relay Everything.
