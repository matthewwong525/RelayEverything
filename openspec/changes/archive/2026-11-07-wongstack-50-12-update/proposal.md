# Update WongStack to 50.12.0

**Status:** shipped
**Branch:** sync-and-ship-change
**Open questions:** none

## Why

This repo runs WongStack 50.10.0. Four releases came out since then (50.10.1 to 50.12.0). The biggest one ships WongStack's own home-proxy routes for the assistant's browser, so this repo can stop keeping its own copy of them.

## What Changes

- **What you get.** The assistant's browser uses WongStack's home-proxy code: your home proxy first, the backup second, then this computer's own network. It works the same as now. Each chat's name now follows its current work, such as the plan's title. The admin app's Access page starts correctly when Cloudflare sends the sign-in rule with no session time, and says why when a start fails.
  ```mermaid
  flowchart TB
    A["Browser page"] --> B["Home proxy"]
    B -- "off" --> C["Backup proxy"]
    C -- "off" --> D["Own network"]
  ```
- **What changes in how you work.** The browser gets an on/off proxy switch. It is already on for this computer, so nothing changes for you. To go straight to sites, say *turn the browser proxy off*: your saved proxies stay for when you turn it on again. The old *network off* step, which erased the saved proxies, goes away.
  ```text
  Before                  After
  ------                  -----
  Routes always on        Routes on while the
                          switch is on (on now)
  "network off" erases    "proxy off" keeps the
  the saved proxies       saved proxies
  ```
- **What of yours stays.** Your saved home and backup proxies stay, with no step. The running browser keeps going as it is: nobody restarts it. The tip on how the assistant uses the keyboard when your turn holds the browser stays. Relay Everything's phone app, website, server and ring do not change.
- **What is left out, and why.** The browser's own route tests leave this repo, because WongStack now owns that code and tests it. The status line that showed the browser's language goes away; the browser still starts in English for your country. No website page changes, because the update changes the assistant's tools, not what the website describes.
- **What you do yourself.** Nothing.

## What the build needs

- **The WongStack source**: Ready, at version 50.12.0 on this computer.
- **The browser proxy switch on this computer**: Ready, already on.

## Capabilities

### New Capabilities

### Modified Capabilities

- `browser-proxy`: the routes apply while the browser's proxy setting is on; `proxy off` replaces `network off` and keeps the saved lines.

## Impact

- 26 changed WongStack parts from the update check: 17 changed with no local edits, 2 new, 7 where this repo has its own edits. Lists are in the design.
- The browser's local route copy (`server.mjs`, `forwarder.test.mjs`) is deleted; upstream's `proxy-lines.mjs` takes its place.
- Admin app Access code and tests change (`app/worker/employee-access/`, `app/src/apps/access/`); the Relay devices line in the login test stays.
- Non-goals: no Relay Everything feature change, no website page, no browser restart.

## Decision log

- **2026-11-07** — Assumed: take WongStack 50.12.0's browser proxy code in full and delete this repo's own route copy, because the release ships the same routes (the proxy-line reader matches `server.mjs` line for line) and its update note says it takes the place of a repo's own copy.
- **2026-11-07** — Assumed: take WongStack's proxy on/off setting this time, because `~/.wong-stack/browser-settings.json` already holds `"proxy": true` on this computer, so every start still goes through the home proxy, as Matthew wants (fact #239).
- **2026-11-07** — Assumed: drop `network off` and `BROWSE_LANGUAGE=`, because `proxy off` gives a way to go direct that keeps the saved lines, and the language line was only a status note: `launch-config.py` still picks English for the address's country.
- **2026-11-07** — Assumed: keep the local *When your turn holds the browser* section in `wiki/development/browsing.md` and the Relay devices lines in `login-management.test.ts`, because both are this repo's own additions that upstream does not replace.
- **2026-11-07** — Assumed: do not restart the running browser, because it already goes through the home proxy and the update note says to ask before a stop.
- **2026-11-07** — Assumed: no other workspace overlaps this update, because the open workspaces change the phone app screens and the texting inbox, not WongStack's shared files.
- **2026-11-07** — Assumed: no Relay Everything website page changes, because the update changes the assistant's tools, not the app, server, ring or connections.
- **2026-11-07** — Check: `.agents/skills/browser/scripts/forwarder.test.mjs` deleted, because it tested `languageLine`, `network off` and `server.mjs`, which are gone; WongStack now owns the route code and tests it in `scripts/tests/`.
- **2026-11-07** — Assumed: take upstream's browser comment in `.env.example`, because the old one still called the routes always on, and the preflight did not list that file; the key names stay blank and the same.
- **2026-11-07** — Archived for shipping; the save before it passed CI on PR #46.
