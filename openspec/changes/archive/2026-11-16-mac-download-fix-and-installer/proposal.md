# Proposal: The Mac app opens, and its download looks like Relay Everything

**Status:** ready-to-ship
**Branch:** mac-dmg-nicer-on-brand
**Open questions:** none

## Why

The Mac app opens to a black window and never shows a note: it can not read its saved key, so it stops before its first screen. Its download also opens as a plain Finder window with two loose icons, so the first thing a person sees is not Relay Everything.

## What Changes

- **The Mac app opens to your notes.** On first open, and on each open after, the window shows the notes list, not a black window. A Mac with no saved key opens signed out, as before.
  ```svg
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 230" width="640" height="230">
    <text x="20" y="22" font-size="14" font-weight="700" fill="#121614">Before</text>
    <rect x="20" y="34" width="280" height="180" rx="10" fill="#000000"/>
    <rect x="20" y="34" width="280" height="22" rx="10" fill="#2B2B2B"/>
    <text x="160" y="50" font-size="11" fill="#CCCCCC" text-anchor="middle">Relay Everything</text>
    <text x="340" y="22" font-size="14" font-weight="700" fill="#121614">After</text>
    <rect x="340" y="34" width="280" height="180" rx="10" fill="#F7F8F4" stroke="#E3E6DF"/>
    <text x="480" y="50" font-size="11" fill="#5E6660" text-anchor="middle">Relay Everything</text>
    <rect x="350" y="64" width="80" height="140" rx="8" fill="#FFFFFF"/>
    <rect x="358" y="74" width="60" height="8" rx="4" fill="#E3E6DF"/>
    <rect x="358" y="90" width="50" height="8" rx="4" fill="#E3E6DF"/>
    <rect x="358" y="106" width="56" height="8" rx="4" fill="#E3E6DF"/>
    <rect x="440" y="64" width="170" height="140" rx="8" fill="#FFFFFF"/>
    <text x="452" y="86" font-size="13" font-weight="700" fill="#121614">Notes</text>
    <rect x="452" y="98" width="140" height="8" rx="4" fill="#E3E6DF"/>
    <rect x="452" y="114" width="120" height="8" rx="4" fill="#E3E6DF"/>
  </svg>
  ```
  No real picture: the Mac app runs only on a Mac, and this computer is not one.
- **The download opens as a Relay Everything window.** A fixed-size window with no toolbar or sidebar: light paper with the logo at the top, the app on the left, a green arrow, and Applications on the right, and under them *Drag Relay Everything to Applications*. The names under the icons are black and easy to read in light and dark mode. The disk shows the Relay Everything icon, not a plain white one. Its colors stay the same in dark mode: the picture is fixed, and only Finder's icon names change.
  ```svg
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 364" width="600" height="364">
  <g transform="scale(0.909)">
    <rect width="660" height="400" rx="12" fill="#F7F8F4"/>
    <g transform="translate(232 34) scale(0.75)" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="4">
      <path d="M14 38V10h10a8 8 0 0 1 0 16H14m10 0 8 12" stroke="#0E7A5A"/>
      <path d="M36 12a10 10 0 0 1 0 12M40 8a16 16 0 0 1 0 20" stroke="#F5A524"/>
    </g>
    <text x="276" y="58" font-size="20" font-weight="700" fill="#121614">Relay Everything</text>
    <rect x="122" y="140" width="96" height="96" rx="22" fill="#0E7A5A"/>
    <text x="170" y="200" font-size="44" font-weight="700" fill="#FFFFFF" text-anchor="middle">R</text>
    <text x="170" y="270" font-size="13" fill="#121614" text-anchor="middle">Relay Everything</text>
    <path d="M262 188h120" stroke="#0E7A5A" stroke-width="5" stroke-linecap="round"/>
    <path d="M372 172l18 16-18 16" fill="none" stroke="#0E7A5A" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
    <rect x="442" y="148" width="96" height="80" rx="10" fill="#6CB4EE"/>
    <text x="490" y="270" font-size="13" fill="#121614" text-anchor="middle">Applications</text>
    <text x="330" y="346" font-size="16" fill="#5E6660" text-anchor="middle">Drag Relay Everything to Applications</text>
  </g>
  </svg>
  ```
  No real picture: the disk image is made only on a Mac build machine, so this is a drawing of it.
- **A pull request's Mac build is the same download.** The file to try from a pull request is the disk image, unsigned, so you can see the window before it goes out.

## What the build needs

- **Nothing.** The background is drawn from the brand files, and the signed build uses the Mac certificate already set up for `main`.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-mac-app`: adds that the app opens to its notes with no saved key or with one, and that the download opens as a branded install window.

## Impact

- `mobile/lib/data/connection.dart` (`KeyVault`): reads each saved name by itself, not with `readAll`, which the Mac's login keychain refuses with `errSecParam` (-50). `mobile/test/fakes.dart` (`MemoryStorage`) gets `read` and an option to refuse `readAll` as the Mac does.
- `brand/make-icons.mjs`: also writes `mobile/macos/dmg/background.png` and `background@2x.png`.
- New `mobile/macos/dmg/settings.py` (dmgbuild layout) and `mobile/macos/dmg/make-dmg.sh`.
- Overlaps the mac-app-updates plan in `mobile-macos.yml` and `install.md`: the dmgbuild `.dmg` is the one file its update feed and the website give; the second to land takes in the other's lines.
- `.github/workflows/mobile-macos.yml`: makes the disk image with dmgbuild on every run; a branch keeps the unsigned image in place of the zip.
- Docs: `mobile/README.md` (the Mac build), `wiki/brand.md` (the script's new output, and why it stays light), the website's Mac install step (`site/src/content/docs/start/install.md`).

## Decision log

- **2026-11-16** — Asked which background the install window uses (Finder's icon names are white in dark mode, black in light) → chose the green band.
- **2026-11-16** — Assumed: the black-window fix goes in this change, because it is the same Mac download and the log named the cause.
- **2026-11-16** — Assumed: dmgbuild over create-dmg, because it needs no Finder automation on the build machine.
- **2026-11-16** — Assumed: the dmgbuild `.dmg` is the one file the mac-app-updates feed and the website give, and the second plan to land takes in the first's lines, because the daily line-up named the overlap.
- **2026-11-16** — Assumed: a pull request keeps the unsigned disk image in place of the zip, so the window can be checked before it goes out.
- **2026-11-16** — Note for the mac-app-updates plan, which had not landed on `main` when this one was built (no Sparkle or `mac-updates` lines in `mobile-macos.yml`): this plan lands first. When mac-app-updates lands, it takes in these lines: the `setup-python` and pinned `dmgbuild` steps, and `macos/dmg/make-dmg.sh "$APP" "$DMG"` in place of `hdiutil create`, run after Sparkle's helpers and the app are signed. Its update feed, the `mac-updates` release and the website give that one signed, notarised `$DMG`, `Relay-Everything-Mac.dmg`. `scripts/app-release.test.mjs` fails on an `hdiutil create`.
- **2026-11-16** — Assumed: the test gate between parts moved to the end, as the build rules say; acceptance is the same.
- **2026-11-16** — Assumed: the window is 660 by 428, not 660 by 400, because the second look found that Finder's window size counts the title bar, which would cut the bottom of the background. Task 3.2's screenshot confirms it.
- **2026-11-16** — Saved for the Mac check: all tasks but 3.2 are done; the pull request's build makes the unsigned disk image that 3.2 checks on a Mac.
- **2026-11-16** — Check: `.github/workflows/mobile-macos.yml` changes the Mac build's steps but loosens no check: dmgbuild replaces `hdiutil create`, and a branch keeps the unsigned disk image in place of the zip, still with `if-no-files-found: error`; the signing, Apple's check, the staple and `mac-check` are unchanged.
- **2026-11-16** — Asked nothing: Matthew's Mac check showed the green band hid the green app icon and made the names hard to read, and that Finder drew the names black in dark mode on this light-topped picture. So the band is gone: all paper, a green arrow, black names in both modes.
- **2026-11-16** — Matthew's Mac check showed the unsigned test copy would not open (`different Team IDs`): a branch now signs every part ad hoc, with no hardened runtime. The signed build is unchanged.
- **2026-11-16** — Check: `.github/workflows/mobile-macos.yml` signs a branch's copy ad hoc with no hardened runtime, because macOS refuses ad hoc frameworks under it; the copy goes nowhere, and main's and a release's signing keep the hardened runtime.
- **2026-11-16** — Asked Matthew how the test copy relay-everything-mac-386 went on his Mac → all good: the light install window looks right and the app opens to its notes.
- **2026-11-16** — Archived at ship: Matthew checked the test copy on a Mac.
