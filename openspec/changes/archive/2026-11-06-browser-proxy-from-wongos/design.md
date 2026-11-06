# Design

## Context

- This repo runs WongStack 50.1.0 since PR #15 (`bfa8357`); its browser scripts equal the source's.
- WongStack 50.1.0's browser has a direct-only forwarder (`forwarder.mjs`, 107 lines, `startForwarder()` with no routes). WongOS (`/root/WongOS/.agents/skills/browser/scripts/`, from WongOS PRs #262 and #264) adds `server.mjs` (`resolveFirst`, `resolveUpstream`, `parseUpstream`, `parseFirst`), a 326-line `forwarder.mjs` (route order, 60 s first-proxy backoff, `NETWORK_FILE`, `networkLine`, `languageLine`, `isLocal`), `forwarder.test.mjs`, the call `startForwarder({ first: resolveFirst(), upstream: resolveUpstream(), networkFile: NETWORK_FILE, extra: { language: 'english' } })` in `browser-server.mjs`, `geoip` and `en-<country>` locale in `launch-config.py`, `status` / `network off` in `browse.mjs`, and `camoufox[geoip]` in the install. WongOS's owner page is `/root/WongOS/knowledge/development/browser-proxy.md`; it names the home IP, so it is a source to read, not to copy.
- The computer files `~/.wong-stack/camoufox/first-proxy` and `upstream-proxy` already exist. The shared browser (pid 2593558) runs from electric-wolverine's older `browser-server.mjs` with locale `en-DE` and no routes.

## Goals / Non-Goals

**Goals:**
- Port the WongOS routes onto the 50.1.0 browser scripts, with tests.
- Keep every proxy line out of git.

**Non-Goals:**
- Restart the running browser. That waits for Matthew's yes, after the build.
- Change WongStack upstream. A later, hand-made contribution may send the routes ([contributing](../../../wiki/contributing.md)).
- Change Relay's app, phone, ring or website behaviour.

## Decisions

- **Port onto 50.1.0.** Apply WongOS's proxy diff as a local layer: the forwarder and `server.mjs` come whole from WongOS; `browser-server.mjs`, `browse.mjs` and `launch-config.py` take only the proxy hunks. Alternative, take WongOS's whole browser: rejected, because WongOS runs 48.0.0 and would undo 50.x browser work (password manager add-ons, no `logins.mjs`).
- **The module name stays `server.mjs`.** It matches WongOS, so a later upstream contribution is one diff. The install record keeps `browser` as the skill name.
- **No address in code, tests or docs.** Tests use `127.0.0.1` listeners only. The wiki page names the keys and files, not a host, provider login or home address. Provider names (a home Pi, a paid upstream) stay generic.
- **The wiki page lives at `wiki/development/browser-proxy.md`**, linked from `browsing.md`, because this repo has no `knowledge/` copy of browsing.
- **A later WongStack sync keeps the routes.** The routes show as locally adapted in a preflight, and a sync merges, never overwrites them.

## Risks / Trade-offs

- [WongOS's proxy hunks assume 48.0.0 lines in `browser-server.mjs` and `browse.mjs`] → port by hand against 50.1.0 and run both forwarder and browse tests.
- [A `geoip` lookup at start needs the `camoufox[geoip]` extra] → the install line adds it; a start with no route uses `en-US`.
- [A restart signs the iPhone chat out of its Apple step] → no restart in this change; the assistant asks Matthew first.
