# Update WongStack to 61.9.1: plans show screens as pages, longer keys, safer schedules

**Status:** ready-to-ship
**Branch:** wong-sync-61-9-1
**Open questions:** none

## Why

This repo runs WongStack 61.7.2. Three releases came out since. 61.8.0 lets the key link take longer keys and any file. 61.9.0 makes a plan show each changed screen as a page in the app's real look, not a sketch. 61.9.1 stops a run from ending a repeating schedule by mistake. Matthew asked to update and publish.

## What Changes

- **What you get: a plan shows a screen as it will look.** A plan that changes a screen writes it as a page in the app's own colors, fonts and words. A phone screen copies the phone app's colors and its Inter font. A plan no longer runs a copy of the app to take pictures, and a card with only a rough sketch does not build.
  ```text
  Before: sketch with grey bars, or test picture
  After:  Before page | After page, real look
  ```
- **What you get: the key link takes longer keys and any file.** A key can be up to 32 KB, such as a signing certificate. A file that is not text, such as a `.p12` file, turns into one line of letters on your own device. The page shows only the file's name and size.
  ```text
  Before: key over 4,096 characters → "Couldn't save this one"
  After:  key up to 32 KB, or any file up to 24 KB → saved
  ```
- **What you get: a run can't end a repeating schedule.** A run of a schedule with no end can no longer finish with *done* and stop the schedule for good. It is refused, and the schedule keeps its next run.
  ```text
  No end + run says --done → refused
  The schedule keeps its next run
  ```
- **What changes in how you work.** Plans for the phone app show pages, not screen test pictures. The steps that draw a phone screen with a screen test stay, for your own checks only.
  ```text
  Phone screen in a plan: page in the phone app's look
  Screen test pictures:   your own checks only
  ```
- **What of yours stays.** The public plugin list still shows only the Relay Everything plugin. The admin pages keep their green. The plan guide keeps its tip to open a live card first, and the design guide keeps its link to the brand page. The website, server, phone app and plugin do not change.
  ```text
  Kept: plugin list, green admin pages, local tips and links
  Unchanged: site, server, phone app, plugin
  ```
- **What is left out, and why.** The update check names the public plugin list as an old WongStack plugin. It is Relay Everything's own list, so it stays, as in the earlier updates. No plan is open, so no plan needs new pages. Codex on this computer has no old WongStack plugin.
  ```text
  Checked, nothing to do:
    public plugin list ... Relay Everything's own, kept
    open plans ........... none
    old Codex plugins .... none
  ```
- **What you do yourself.** Nothing. After the publish, the chat restarts the background helper in the main folder so schedules use the new code.
  ```text
  1. publish
  2. chat restarts the helper in the main folder
  ```

## What the build needs

- **The WongStack source**: Ready, version 61.9.1 at commit `88730bba` on this computer.
- **Your yes to publish**: Ready. Matthew asked to update and publish.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared tools and this repo's own notes on plan pictures, and no requirement in `openspec/specs/` covers them. The change sets `skip_specs: true`.

## Impact

- 21 of 774 WongStack parts changed (preflight `status: update`, `catchUp.needed: true` for `module-plugin` on `.claude-plugin/marketplace.json` only, `updatingComplete: true`): 17 `installed-equivalent` and `latest-equivalent` files copied whole, 1 removed (`plan/scripts/prototype.mjs`), 3 `locally-adapted` merged by hand. List in the design.
- 61.9.0's target impact: this repo's own phone screen test steps for plan pictures. `.agents/skills/plan/SKILL.md`, `.agents/rules/mobile.md`, `wiki/review-pages.md` and `wiki/development/phone-pictures.md` stop sending a plan to them.
- No route, `relay_*` table, settings, hook, memory database, site, mobile or plugin change.

## Decision log

- **2026-11-17** — Assumed: build and publish with no further question, because Matthew asked to ship this update all the way to live.
- **2026-11-17** — Assumed: no spec delta (`skip_specs: true`), because no Relay Everything requirement covers WongStack's tools or plan pictures.
- **2026-11-17** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-17** — Assumed: keep `.claude-plugin/marketplace.json`, which the catch-up names, because it lists only the Relay Everything plugin ([WongStack updates](../../../../wiki/development/wongstack-updates.md)); no `enabledPlugins` `@skills-dir` key exists in `.claude/settings*.json`.
- **2026-11-17** — Assumed: drop the local phone screen test lines from the plan guide, the mobile rule and the review pages wiki, and keep `phone-pictures.md` for own checks only, because 61.9.0 says a repo's own screen test picture steps are no longer read for plans. Upstream's prototype guide already names `mobile/lib/brand.dart` and the Inter font for a phone page.
- **2026-11-17** — Assumed: keep the local live-card tip in `drawings.md` and the brand link in `ux-principles.md`, because they are Relay Everything's own lines and 61.9.0 does not touch them.
- **2026-11-17** — Found: no open plan in `openspec/changes/`, so 61.9.0's note about open plans with sketches needs nothing here.
- **2026-11-17** — Found: `codex-plugin.mjs --check` prints nothing, so the last task removes nothing.
- **2026-11-17** — Found: no open memory thread on sync is reached by this update. The memory tidy thread (#995) belongs upstream.
- **2026-11-17** — Assumed: after the publish, reinstall the background helper in `/root/relay-ring` at a quiet minute, because 61.9.1 changes the schedule code it runs ([WongStack updates](../../../../wiki/development/wongstack-updates.md)).
- **2026-11-17** — Assumed: run the site and server publish scripts after the publish, because `AGENTS.md` asks for both after each publish.
- **2026-11-17** — Archived inside `/ship` at `openspec/changes/archive/2026-11-17-wongstack-61-9-1-update`, branch `wong-sync-61-9-1`: 17 files copied equal to `install-path.mjs`, `prototype.mjs` removed, three local files merged with their local lines kept, the phone screen test no longer feeds plans, merge check clean, public check, product-name test and local checks pass, the install record says 61.9.1 and the preflight reports `status: current`; Codex had no WongStack plugin. The second look found one broken link in the design, now fixed.
