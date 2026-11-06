# Tasks

## 1. The browser routes

- [x] 1.1 Add WongOS's `server.mjs`, `forwarder.mjs` and `forwarder.test.mjs` to `.agents/skills/browser/scripts/`. Verify: `node --test .agents/skills/browser/scripts/forwarder.test.mjs` passes.
- [x] 1.2 Port the proxy hunks into the 50.1.0 `browser-server.mjs` (forwarder start with first and upstream routes, network file, language), `launch-config.py` (`geoip`, `en-<country>` locale) and `browse.mjs` (`BROWSE_NETWORK=`, `BROWSE_LANGUAGE=`, `network off`, `camoufox[geoip]` install). Port their tests from WongOS. Verify: `node --test .agents/skills/browser/scripts/` passes, and `browse.mjs status` prints `BROWSE_NETWORK=` without a restart.
- [x] 1.3 Add blank `BROWSE_FIRST_PROXY=` and `BROWSE_UPSTREAM_PROXY=` to `.env.example`. Verify: both values are empty.
- [x] 1.4 Write `wiki/development/browser-proxy.md` (route order, where the lines come from, status values, turn it off) with no address, login or provider account; link it from `wiki/development/browsing.md` and the browser `SKILL.md`. Verify: the wiki link check passes.

## 2. Checks

- [x] 2.1 Run `node scripts/public-check.mjs` and search the diff for any IPv4 other than `127.0.0.1`, any `@host:port` line and the provider's host name. Verify: `result=` is not `refused` and the search finds nothing.
- [x] 2.2 Run the repo's checks and tests. Verify: all pass.

## After publish

These steps run after `/ship` merges, so they carry no checkbox.

- 3.1 Ask Matthew before a browser restart; after a yes, restart and run `browse.mjs status`. Verify: `BROWSE_NETWORK=upstream` and the locale is `en-CA`.
- 3.2 Offer to send the routes to WongStack by hand ([contributing](../../../wiki/contributing.md)).
