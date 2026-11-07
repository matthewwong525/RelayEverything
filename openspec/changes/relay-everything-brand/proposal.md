# Give Relay Everything its own look: an electric R and rich colors for the app and the website

**Status:** in-progress
**Branch:** brand-app-ui-cleanup
**Open questions:** none

## Why

The phone app wears Flutter's stock purple-blue, and the website's logo is a ring, which no longer fits: the app comes first, not the ring. Before we clean up the notes screen and the other screens, Relay Everything needs one look to clean them up toward: a logo, colors, type and a few rules that every screen follows.

## What Changes

- **A brand board you can tap through.** It shows five takes on a capital R, each with a relay or a circuit in it: *Relay R* (the leg is a relay switch), *Trace R* (routed like a circuit board), *Rooted R* (three pins join into the stem), *Signal R* (the bowl sends out waves) and *Bolt R* (the leg is a bolt of current). Small spark pulses run along the wires. It also shows three color sets (*Emerald*, a deep green; *Signal*; *Volt*), the app icon, the type and the rules for every screen. Tap a logo and a color set: the whole board changes, and your pick comes back with your notes. Tap *Dark* to see the dark colors.
  ```live
  folder: prototypes/brand
  height: 1600
  ```
- **The app wears the brand.** Clean paper white and ink in place of the purple tint. The main color goes on the one main action, such as *New note*, with a soft glow. The spark color marks small live moments, such as a voice note or recording. The app gets the Inter font and the logo beside the name at the top. Dark mode gets its own deep colors, where the main color glows. The Android share card uses the same look; the iPhone share sheet keeps the phone's own look for now. The layout of each screen stays as it is: the next plan cleans it up. Section 6 of the board shows the notes screen after.
  ```picture
  Before: pictures/before-timeline.webp
  Before, new note: pictures/before-new-note.webp
  ```
  These are today's screens from the last iPhone check. The *After* is the board's section 6, because the phone app does not run in the plan's preview.
- **A new app icon.** The R in white on the main color, on iPhone and Android (dark ink on *Signal*'s cyan). The launch screen turns paper white, with the logo in the center. The icon stays still; the moving pulse is only for the board now, and later for the app's *Syncing* state.
  ```screen
  <div class="row gap">
    <div class="card col gap"><span class="tag">Icon</span><span class="muted">Main color, white R</span></div>
    <div class="card col gap"><span class="tag-outline">Launch screen</span><span class="muted">Paper white, logo in the center</span></div>
  </div>
  ```
- **The website wears the brand.** relayeverything.com gets the new logo in the top bar and the browser tab, the main color in place of the blue, and Inter. The home page's phone-to-database picture takes the main color and the spark. The words and pages stay the same.
  ```screen
  <div class="card col gap">
    <div class="row gap"><span class="tag">Logo</span><h3>Relay Everything</h3><span class="grow"></span><span class="muted">Search</span></div>
    <div class="sep"></div>
    <h3>Your data, in a place you choose.</h3>
    <span class="muted">Relay Everything keeps your notes on your phone. When you choose, it sends them to your own server, where your own AI can read them.</span>
    <div class="row gap"><button class="btn-primary">Get started</button></div>
  </div>
  ```
- **One brand page that every later change follows.** A short page in the wiki says the colors, the type, how to use the logo, and the four rules for every screen. The next plan, *clean up the notes screen and the app*, starts from it. A check makes sure every text color stays easy to read on its background, in light and in dark.
  | Rule | What it means |
  |---|---|
  | One bright thing | The main color marks the one main action on a screen. The spark is for small live moments. Everything else is ink or muted. |
  | Cards, no borders | A card is a lighter shape on paper. No box inside a box. |
  | Words with every color | A state says its name: *Synced*, *Waiting*, *Off*. Never color alone. |
  | Soft corners | 12 px on buttons and fields, 16 px on cards. |

Non-goals: moving or removing anything on a screen (the next plan); the Relay Everything page on your server, which keeps the app's shared look for now; the ring's own pictures and pages on the website; a new name.

## What the build needs

- **Your logo and color pick**: Ready. You picked *Signal R* and *Emerald* on the board.
- **The Inter font**: Ready. It is free under the SIL Open Font License; the build copies it into the app and the website with its license, so the app stays offline.
- **App Store Connect key for TestFlight builds**: Ready, in `.env` and the repository's secrets. The new icon goes out with the next TestFlight build.

## Capabilities

### New Capabilities

- `relay-brand`: the brand's colors, type, logo and app icon, and the promise that the app, the Android share card and the website use them, with readable contrast in light and dark.

### Modified Capabilities

None.

## Impact

- `mobile/`: a brand theme file used by `app.dart` and `share/share_main.dart`; Inter in `mobile/assets/fonts/` with its license; iOS `AppIcon.appiconset`, Android `mipmap-*` launcher icons, iOS `LaunchScreen.storyboard` and Android `launch_background.xml`; a theme contrast test.
- `brand/`: the logo and icon source SVGs, and a script that makes the icon PNGs from them.
- `site/`: `custom.css` colors and font, a new logo SVG in `src/assets/`, `public/favicon.svg`; `astro.config.mjs` points at the new logo; the home page's hero SVG in `src/content/docs/index.mdx` loses its fixed blue.
- `wiki/brand.md`, linked from `wiki/README.md` and `wiki/ux-principles.md`.
- No server, data, route or key change.

## Decision log

- **2026-11-07** — Asked what Relay Everything should feel like → chose *Calm and private*: warm paper, ink, one deep green accent, quiet type.
- **2026-11-07** — Asked what idea the logo should carry → chose *Many into one*; the board shows three marks of that idea to pick from.
- **2026-11-07** — Asked how to split the work → chose *Brand first, then UI*: this plan is the brand; a second plan cleans up the notes screen and the other screens with it.
- **2026-11-07** — Assumed: the ring circle logo goes everywhere it stands for the product, because Matthew said on 2026-11-05 that branding should not depend on the ring.
- **2026-11-07** — Assumed: this plan changes colors, type, logo and icon only, not layout, because the layout cleanup is the second plan and mixing them makes both harder to review.
- **2026-11-07** — Assumed: Inter as the one font, bundled in the app, because the app makes no network call with sending off, so it can not fetch a font.
- **2026-11-07** — Assumed: the server's Relay Everything page keeps the app's shared look, because it shares that look with the other mini apps and a WongStack update would undo a local restyle.
- **2026-11-07** — Assumed: a deterministic script makes the icon PNGs from one SVG, because the icon comes in about 30 sizes and will change again.
- **2026-11-07** — Asked, in notes on the plan, for livelier colors: *Calm and private* looked dull → changed to three bright color sets on the board (*Live wire*, *Signal*, *Volt*), each with one bright main color and a small spark color, contrast checked in light and dark; *Live wire* is the default.
- **2026-11-07** — Asked, in notes on the plan, for a more creative *Converge* logo with real relays, circuit diagrams, or an R or r → replaced the three marks with five: *Switch*, *Traces*, *Relay R*, *Circuit r* and *Broadcast*; *Switch* is the default.
- **2026-11-07** — Assumed: a bright main color (*Signal*'s cyan) fills buttons with dark ink text, and a deeper shade is used for text on paper, because white text on a bright cyan is hard to read.
- **2026-11-07** — Assumed: the spark pulse moves only on the board for now, because a moving logo in the app is a layout and motion choice for the next plan.
- **2026-11-07** — Asked, in notes on the plan, for more capital-R logos (*that's the play*) → the board now shows only capital Rs: *Relay R*, *Trace R*, *Rooted R*, *Signal R* and *Bolt R*; *Relay R* is the default.
- **2026-11-07** — Asked, in notes on the plan: the green felt too bright and distracting → *Live wire* became *Emerald*, a deep green (`#0E7A5A`) with white button text and the amber spark; it is the default.
- **2026-11-07** — Asked, on the review page, which logo and colors to ship → chose *Signal R* and *Emerald*.
- **2026-11-07** — Assumed: headless Chromium draws the icons and ImageMagick only sizes them, because ImageMagick's own SVG renderer drops paths and stroke colors.
- **2026-11-07** — Assumed: Android 12 and later get the paper launch color through `values-v31` styles, and the adaptive icon gets a one-color layer for themed icons, because without them Android 12 shows its own launch color.
- **2026-11-07** — Assumed: the app bar title is 20 px at weight 650 beside a 24 px mark, because at weight 700 the name cut off on a 360 px phone.
- **2026-11-07** — Assumed: Material's 14 px body and label sizes stay, and body text drops Material's added letter spacing, because 16 px everywhere moves screens, which is the next plan.
- **2026-11-07** — Assumed: the website's dark accent for links and the main button is the dark accent text (`#4CC79A`), not ink, because Starlight uses that value as the dark link color.
- **2026-11-07** — Assumed: the iPhone share sheet, which is native SwiftUI, keeps the phone's own look; the Android share card wears the brand, because restyling the native sheet needs its own font bundle and a build to check.
- **2026-11-07** — Checkpoint: built with *Signal R* and *Emerald*; local checks pass; saved for the iPhone check and the website preview (tasks 1.3 and 5.2).
- **2026-11-07** — Assumed: the *Typed* tag is accent text on accent-soft and the *Listening* microphone is on-spark, because board section 6 shows that tag so and an ink icon on spark breaks the one-color chip.
- **2026-11-07** — Assumed: `brand/make-icons.mjs` keeps the wordmark outlines it finds in `brand/logo.svg` and redraws only the mark and colors, because the outlines have no other source and the font is not in the repository's build tools.
- **2026-11-07** — Assumed: the favicon keeps its 16-unit round corners while `brand/icon.svg` stays full bleed, because a browser tab shows the picture as it is and no platform rounds it.
- **2026-11-07** — Assumed: the old-blue check reads built `.svg` files as well as `.html` and `.css`, because a picture in `public/` can carry the old color too.
- **2026-11-07** — Checkpoint: the second look's three fixes (spark on the Voice and Listening chips, one script for every logo file, the old-blue check on whole pages) saved.
