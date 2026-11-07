# Design: Update WongStack to 50.12.0

## Context

See proposal.md, Why. Source: `/root/.cache/wong-stack/WongStack` at `2acdf24b018a3596186316cc29a91ccfb40384b7` (VERSION 50.12.0), refreshed on 2026-11-07 (already up to date). Installed: 50.10.0 at `1d14a762d2bc132ed78f054aec8adeca3cb4e406`. The preflight (schema 1, `status: update`, categories core, ui, pack and scaffold, `catchUp.needed: false`, no diagnostics, 367 ms) found 26 changed units of 690.

`CLAUDE.md` already links to `AGENTS.md`, and `.claude` links to `.agents`. Logical `.claude/…` paths below are real files under `.agents/…`.

## Goals / Non-Goals

- Goal: every changed unit takes the 50.12.0 version, or a merge of it with this repo's own lines.
- Goal: the browser keeps going through the home proxy on this computer.
- Non-goal: any Relay Everything behavior change, any website page, or a browser restart.

## Decisions

### Unit routes, by preflight class

| Class | Count | Route |
|---|---|---|
| modified / installed-equivalent | 17 | Copy the source file over the target file. |
| added / missing | 2 | Copy. |
| locally-adapted | 7 | Merge by hand, below. |

Installed-equivalent (17): `.claude/skills/{apply,explore,plan,ship}/SKILL.md`, `.claude/skills/explore/scripts/step-title.mjs`, `.claude/skills/memory/references/areas.json`, `.claude/skills/wong-sync/references/payload-files.json`, `app/src/apps/access/Notices.tsx`, `app/src/lib/access.ts`, `app/worker/employee-access/{login-management.ts,management.ts,management.test.ts,start.ts,start.test.ts}`, `wiki/development/the-change-loop.md`, `wiki/stack/{company-knowledge.md,employee-access.md}`.

Added (2): `.claude/skills/browser/scripts/proxy-lines.mjs`, `app/src/apps/access/Notices.test.tsx`.

### The browser: take upstream, drop the local copy

WongStack 50.12.0 ships the routes this repo ported from WongOS. `proxy-lines.mjs` equals the local `server.mjs` except for comments and line wrapping, and upstream `forwarder.mjs` keeps the same route order, one-minute skip and no-resend rule.

- Copy upstream `SKILL.md`, `browse.mjs`, `browser-server.mjs`, `forwarder.mjs`.
- Delete `.claude/skills/browser/scripts/server.mjs` (replaced by `proxy-lines.mjs`) and `forwarder.test.mjs` (tests `languageLine`, `network off` and `server.mjs`, which are gone; upstream tests these files in `scripts/tests/`).
- Lost on purpose: `network off`, `BROWSE_LANGUAGE=`, the `extra: { language }` field. English still comes from `launch-config.py`, which is unchanged.
- The proxy setting already reads on: `~/.wong-stack/browser-settings.json` holds `{"proxy":true}`. No hand step. The running browser started with the local code, which writes no `proxy` key in `server.json`; upstream status reads a missing key as on, so it prints no restart note.

### Wiki merges

- `wiki/development/browser-proxy.md`: take upstream text. Drop the local "WongStack does not ship these routes … leave out the setting" paragraph and the local test section. Add one line under the intro: on Matthew's computers the proxy setting stays on, so every start goes through the home proxy.
- `wiki/development/browsing.md`: take upstream's *The proxy setting* section and refusal wording; keep the local *When your turn holds the browser* section.
- `wiki/development/browser-window.md` (not in the preflight, but its text names the old routes): take upstream lines 60, 63 and 66 so the settings file names the proxy setting and the old `#save-the-routes` anchor goes.
- `wiki/development/README.md`: rename the link text *browser routes* to *browser proxies* to match the page title.

### `login-management.test.ts`

Add upstream's import of `admittedEmails` and the new no-session-time test. Keep this repo's *Relay devices* policy lines: Relay Everything has that old machine policy, upstream does not.

### Checks

`npm test` in `app/` covers the access code and tests, plus `public-check --tree`. No browser test stays in this repo. The merge check then names only intended gaps: none expected after the copy.

## Risks / Trade-offs

- [A computer with the proxy setting off would go direct] → This is the only computer that runs the browser for this repo, and its setting is on; the wiki line says to keep it on.
- [No route tests in this repo] → Upstream owns and tests the route code; this repo no longer edits it.
