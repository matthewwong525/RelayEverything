# Proposal: Browser proxy from WongOS

**Status:** archived, publishing
**Branch:** outgoing-starfish
**Open questions:** none

## Why

The assistant's browser in this repo goes straight out from the server, so sites see a data-centre address. Apple signed the shared browser out during the iPhone TestFlight setup, and a data-centre address makes that more likely. WongOS already sends its browser through the home Pi first, then a Canadian backup. Matthew asked for the same routes here.

## What Changes

**What you get**

- **The browser goes out through your home first.** Each new browser start uses the same routes as WongOS: the home Pi, then the Canadian backup, then this server's own network as the last choice. The browser's language and time zone follow the address that sites see.
  ```mermaid
  flowchart TD
    B[Browser] --> F[Home Pi]
    F -- fails --> U[Canadian backup]
    U -- fails --> D[This server]
  ```
- **The status tells you which route is live.** A browser status check says *upstream*, *upstream (backup)*, or *direct*, so you know when the Pi is off.

**What changes in how you work**

- **Nothing, until the next browser start.** Then the browser uses the new routes on its own.

**What of yours stays**

- **The browser's other parts stay as WongStack 50.1.0 made them.** Only the route parts change.
- **The running browser is not touched.** The iPhone chat waits on an Apple code in it now. The new routes start at the next browser start, and only after you say yes to a restart.

**What is left out, and why**

- **No address goes in the repo.** The repo is public, so the proxy lines stay in this computer's saved files and the private settings file. The repo gets only the blank names.
- **The routes are not in WongStack yet.** They exist only in WongOS. You can send them to WongStack by hand later, and then other repos get them from an update.

**What you do yourself**

- **Say yes before a browser restart.**

## What the build needs

- **The proxy lines**: Ready. This computer's saved files already hold both lines, so the repo needs no key.

## Decision log

- **2026-11-06** — Matthew chose: the WongStack 50.1.0 update ships first (PR #15), then this plan builds on the updated browser.
- **2026-11-06** — Assumed: copy the routes from WongOS into this repo now, and offer to send them to WongStack by hand later, because WongStack 50.1.0 does not have them and Matthew wants them now.
- **2026-11-06** — Assumed: no browser restart in this change without Matthew's yes, because the iPhone chat waits on an Apple code in the running browser.
- **2026-11-06** — Assumed: the save step and the two after-publish steps leave the checklist, because `/ship` runs the save and the after-publish steps can not run before the merge.
- **2026-11-06** — Assumed: the browsing page now bans a change of address to get past one refusal, not every hired address, because the routes Matthew asked for use a paid upstream.
- **2026-11-06** — Assumed: the review's one finding (a plain request that fails at the first proxy) is fixed in the wiki and spec, not in the code, because the code matches WongOS on purpose.
- **2026-11-06** — Archive checkpoint: built and reviewed; 25 browser tests pass locally, the public check is clean, and the shared browser was not restarted.

## Capabilities

### New Capabilities

- `browser-proxy`: the shared browser's routes out (first proxy, upstream, direct), where their lines come from, the status line, and the public-repo limits.

### Modified Capabilities

None.

## Impact

- Browser skill, `.agents/skills/browser/scripts/` (now WongStack 50.1.0): WongOS's `server.mjs` (new: `resolveFirst`, `resolveUpstream`), `forwarder.mjs` (routes, first-proxy backoff, network file), `forwarder.test.mjs`; the proxy hunks in `browser-server.mjs`, `launch-config.py` (`geoip` locale) and `browse.mjs` (`status`, `network off`, `camoufox[geoip]` install).
- `.env.example`: blank `BROWSE_FIRST_PROXY=` and `BROWSE_UPSTREAM_PROXY=`.
- Wiki: a new `wiki/development/browser-proxy.md`, linked from `wiki/development/browsing.md` and the browser `SKILL.md`.
- The WongStack install record stays at 50.1.0; the routes are a local adaptation.
