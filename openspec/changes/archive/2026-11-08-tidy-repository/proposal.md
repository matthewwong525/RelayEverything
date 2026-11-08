# Proposal: Tidy the repository so GitHub shows only Relay Everything's software

**Status:** ready-to-ship
**Branch:** clean-up-public-repo
**Open questions:** none

## Why

The GitHub page shows 20 top-level folders and files, and several of them are not what a visitor comes for: the ring's board, a 5.7 MB parts library used only by that board, the ring's 3D models, and a `self-host/` folder whose name does not say what it is. The front page should show the app, the phone app, the website and the plugin, with a short README that says what each one is.

## What Changes

- **The ring hardware leaves the repository.** The board files (`pcb/`), the parts library (`vendor/`) and the 3D models (`cad/`) go. Their past versions stay in the project's history on GitHub, so nothing is lost. The ring pages on the website stay, with their pictures, but no longer link to files on GitHub.
  ```text
  Before                   After
  app/                     app/  (+ self-host/)
  brand/                   brand/
  cad/       removed       mobile/
  mobile/                  openspec/
  openspec/                plugin/
  pcb/       removed       schema/
  plugin/                  scripts/
  schema/                  site/
  scripts/                 wiki/
  self-host/ moved
  site/
  vendor/    removed
  wiki/
  ```
- **"Run your own server" moves inside the app.** `self-host/` is the tool that installs Relay Everything in a person's own Cloudflare account, instead of using app.relayeverything.com. It moves to `app/self-host/`, beside the server it installs. It works the same way, and the website's *Run your own server* page points to the new place. A person who installed before keeps their install: the first run at the new place picks up their old settings.
- **The README becomes a short, clean front page.** One line on what Relay Everything is, a link to the website, a table of the parts that are left, how to run the checks, and the license. No line about the ring's files.
- **The project's rules and wiki stop naming the removed folders.** The first paragraph of the project rules, the *Open source* wiki page and the website wiki page say what the repository holds now.

Non-goals: rewriting the project's history to erase the old files; moving or removing the AI tooling (`.agents/`, `openspec/`, the dev wiki) or the admin app; moving `schema/` or `brand/`.

## What the build needs

- **Nothing.**

## Decision log

- **2026-11-08** — Asked what happens to the ring's 3D models and where the board files go → chose all ring hardware out: `pcb/`, `vendor/` and `cad/` are removed.
- **2026-11-08** — Asked what happens to `self-host/` → chose keep it and tuck it away inside `app/`.
- **2026-11-08** — Asked how far the clean-up goes → chose tidy the front page and keep the AI tooling.
- **2026-11-08** — Assumed: `schema/` stays at the top, not inside `app/` as first offered, because the WongStack update (`/wong-sync`) owns 21 files there by path, and a move would conflict with every update.
- **2026-11-08** — Assumed: `brand/` stays at the top, not inside `site/` as first offered, because its icon script writes the phone app's icons as well as the website's, so it belongs to neither.
- **2026-11-08** — Assumed: the `.codex` link and `paseo.json` stay, because the WongStack tooling installs and reads them.
- **2026-11-08** — Assumed: the old files stay in git history, with no history rewrite, because a rewrite changes every commit ID, breaks every open branch and the six open workspaces, and the files hold nothing private.
- **2026-11-08** — Assumed: the website's ring pages and their pictures stay and drop their GitHub links; `site/scripts/render-ring.sh` and its `render-ring` npm script go, because they render from `cad/`.
- **2026-11-08** — Assumed: `setup.mjs` moves an existing install's git-ignored files (`wrangler.jsonc`, `wrangler.mcp.jsonc`, `wrangler.spaces.jsonc`, `.env`) from the old `self-host/` folder on its first run, because without them `update` says *no install here*.
- **2026-11-08** — Check: `app/package.json` runs the setup tool's tests as `self-host/*.test.mjs` instead of `../self-host/*.test.mjs`, because the folder moved into `app/`; the same tests still run, nothing is skipped.
- **2026-11-08** — Check: `cad/relay-click-test.scad` is deleted, because it is the ring's click-test print model, not a code test; the ring's models left the repository.
- **2026-11-08** — Check: `cad/relay-wear-test.scad` is deleted, because it is the ring's wear-test print model, not a code test; the ring's models left the repository.
- **2026-11-08** — Assumed: `.gitignore` also ignores a top-level `/self-host/`, because an old install's settings sit there after a pull until `setup.mjs` moves them, and they must not show as new files to commit.
- **2026-11-08** — Assumed: `oxlint` now reads `app/self-host/`, and three old comment lines over 120 characters were wrapped rather than the folder ignored, because the fix is two line breaks and keeps every rule on.
- **2026-11-08** — Built inside /ship; the second look found 3 small problems (a weak old-install test, a failed move missing its `result=` line, one old path in a comment), all fixed; saved for CI and the staging check (task 4.3).
- **2026-11-08** — Task 4.3 passed: CI passed on f878069 (PR #60), and the staging website shows *Run your own server* naming `app/self-host/SETUP.md`, with no ring file links.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-open-source`: the repository no longer holds copied libraries, so the scenario about `vendor/` says a copied library, if any, keeps its own license.
- `relay-self-host`: an install made before the setup tool moved inside the app updates with its own settings, with no step from the person.

## Impact

- **Removed:** `pcb/`, `vendor/`, `cad/`, `site/scripts/render-ring.sh` and the `render-ring` script in `site/package.json`; the STL and `__pycache__/` lines in `.gitignore`.
- **Moved:** `self-host/` → `app/self-host/`, with its paths in `setup.mjs`, the two tests, the templates, `app/package.json`'s test line, `app/vite.config.ts`, `app/src/relay-only.tsx`, `app/worker/relay-only.ts`, `.gitignore`, and `scripts/product-name.test.mjs`. App lint, `knip` and `jscpd` must accept the new folder.
- **Docs:** `README.md`, `AGENTS.md` (project paragraph and STL rule), `wiki/open-source.md`, `wiki/relay-website.md`, `site/src/content/docs/start/run-your-own.md`, `site/src/content/docs/ring/board.md`, `site/src/content/docs/ring/models.md`.
- **Website:** republished after the merge, since *Run your own server* names the new path.
