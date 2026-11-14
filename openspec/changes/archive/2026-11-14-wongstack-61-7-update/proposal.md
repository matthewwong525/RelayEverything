# Update WongStack to 61.7.0: a green check in the browser, a design guide, and the admin pages in Relay Everything's green

**Status:** ready-to-ship
**Branch:** sync-wongstack-and-ship
**Open questions:** none

## Why

This repo runs WongStack 61.5.0. Two releases came out today. 61.6.0 adds `/ui`, one step for all screen work, a design guide, and checks that keep every screen readable and in its own colours. 61.7.0 makes the browser's *Hand back* button a green check. You asked to update and publish.

## What Changes

- **What you get: a green check when you give the browser back.** The *Hand back* button becomes a green check at the right end of the toolbar. It counts the tabs that wait on you, and it is grey when nothing waits. The 🔔 stays on each tab that needs you. Each line that hands you the browser says *tap ✅ at the top right*. uBlock Origin still blocks ads, but its button moves into the puzzle-piece menu.
  ```text
  Before:  [uBlock] [1Password] [Hand back 2]
  After:            [1Password] [✅ 2]

  "Sign in, then tap ✅ at the top right"
  ```
- **What you get: one step for screen work, and a design guide.** Before the assistant builds or changes a screen, it reads the UX principles, the new design guide, the ready-made parts, and web guidance at need. You can type `/ui` too.
  ```text
  /ui
   1 UX principles
   2 design guide
   3 ready-made parts
   4 web guidance, at need
  ```
- **What you get: the admin pages wear Relay Everything's green.** The admin app, the plan review pages and the private key pages take the new starter look: rounder corners, softer shadows, larger titles. Their main buttons use the brand's deep green, not the starter's violet. The public website and the phone app do not change.
  ```text
  Admin page, main button
  Before: [ Save ]  black, square corners
  After:  [ Save ]  deep green #0E7A5A,
                    rounder corners, soft shadow
  ```
- **What changes in how you work.** The app's checks now fail when a screen uses a colour outside the app's set, a style on one element, or a class that makes no style. They also fail when text on the green, the page or grey text is hard to read. Today every admin screen passes all four rules, so no screen needs a fix.
  ```text
  App checks, tried on today's screens
    colour outside the set ...... 0
    style on one element ........ 0
    class that makes no style ... 0
    class the check can't read .. 0
  ```
- **What of yours stays.** Your own text on four pages and in the memory areas list stays, and the update adds its new lines beside it. The public plugin list still shows only the Relay Everything plugin. The website, server and phone app do not change.
  ```text
  Kept as they are
  ----------------
  Relay Everything site, server, phone app, plugin
  Public plugin list: Relay Everything only
  Local edits on 4 pages: kept, new lines added
  ```
- **What is left out, and why.** The update check names the public plugin list as an old WongStack plugin. It is Relay Everything's own list, so it stays, as in the last three updates. Codex on this computer has no old WongStack plugin, so that step removes nothing. The starter's violet stays out, because the admin pages belong to Relay Everything.
  ```text
  Checked, nothing to do:
    public plugin list ...... Relay Everything's own, kept
    old Codex plugins ....... none left
    violet accent ........... replaced by the brand green
  ```
- **What you do yourself.** Nothing. The green check shows at the browser's next start.
  ```text
  1. publish the update
  2. next browser start → green check, tidier toolbar
  ```

## What the build needs

- **The WongStack source**: Ready, version 61.7.0 at commit `ea0af925` on this computer.
- **Your yes to publish**: Ready. You asked to update and publish.
- **The brand colours**: Ready, from the brand page's *Emerald* set.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared tools and the admin app's look, and no requirement in `openspec/specs/` (checked: `relay-brand` covers the phone app, the share card and the website; `relay-web-app` is the Flutter web app, not the admin app). The change sets `skip_specs: true`.

## Impact

- 29 of 774 WongStack parts changed (preflight `status: update`, `catchUp.needed: true` for `module-plugin` on `.claude-plugin/marketplace.json` only, `updatingComplete: true`): 22 `modified` / `installed-equivalent` copy whole, 3 `added` copy new, 1 `removed` deletes, 4 `locally-adapted` merge by hand. Groups are in the design.
- `app/src/index.css` takes the upstream brand list with the Emerald accent in `--primary`, `--primary-foreground` and `--ring`; `wiki/brand.md` names the admin app as a fifth colour home.
- `app/.oxlintrc.json` turns on four `shadcn/*` design rules; a trial run found no failure.
- No route, `relay_*` table, settings, hook, memory database, site, mobile or plugin change.

## Decision log

- **2026-11-14** — Assumed: build and publish with no further question, because the person ran `/wong-sync /ship`.
- **2026-11-14** — Assumed: the admin app's accent is the brand's Emerald (`#0E7A5A` / on-accent `#FFFFFF` light, `#4CC79A` / `#06281A` dark, ring the accent), not the starter's violet, because 61.6.0 offers the look without forcing it, and the brand page says one deep green marks the main action. Paper, ink and muted stay the starter's greys, which pass the readable-colour check, and the font stays the device's own: the admin app ships no Inter.
- **2026-11-14** — Assumed: no spec delta (`skip_specs: true`), because no Relay Everything requirement names the admin app's look.
- **2026-11-14** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-14** — Assumed: keep `.claude-plugin/marketplace.json`, which the catch-up names, because it lists only the Relay Everything plugin (decided in the 55.2, 61.0 and 61.5 updates).
- **2026-11-14** — Assumed: `wiki/design-guide.md` copies verbatim, with its *Starter default: a violet* row, because that row names the starter; `wiki/brand.md` records this install's own accent, so the guide stays equal to upstream.
- **2026-11-14** — Assumed: link the design guide from `wiki/README.md`'s wiki list beside UX principles, because this repo's README has its own shape and the new page needs a parent.
- **2026-11-14** — Found: `codex-plugin.mjs --check` prints nothing, so the last task removes nothing. A trial lint run with the four new rules on today's `app/` found no failure, and a planted `bg-pink-500` failed as expected.
- **2026-11-14** — Check: `app/.oxlintrc.json` turns on four `shadcn/*` design rules and loosens nothing, because 61.6.0 adds them to keep each screen in the app's own colours; the lint is stricter, not looser.
- **2026-11-14** — Assumed: run the site and server publish scripts after the publish, because `AGENTS.md` asks for both after each publish.
- **2026-11-14** — Archived inside `/ship` at `openspec/changes/archive/2026-11-14-wongstack-61-7-update`, branch `sync-wongstack-and-ship`: 29 WongStack parts in (24 copied equal to `install-path.mjs`, 4 merged by hand, `bell.svg` removed), merge check names only the starter violet lines left out for the Emerald accent, app lint, type check, `style.test.ts` 8/8, `check-app-checks.mjs`, public check, product-name test and wiki links pass, the install record says 61.7.0 and the preflight reports `status: current`; Codex had no WongStack plugin. The second look found nothing.
