# Move Relay to a public RelayEverything repo on GitHub

**Status:** in-progress
**Branch:** relay-everything-data-hub
**Open questions:** none

## Why

Relay is meant to be open: anyone should be able to read its code, run their own server and send changes. Today the project is private and kept in Cloudflare, only the phone app is public, in a separate repo with no license, and nobody else can see or check a change. One public repo with a license makes Relay open source for real, and lets GitHub run every check and phone build for free.

## What Changes

- **One public repo: github.com/matthewwong525/RelayEverything.** It holds everything: the server and web app, the phone app, the website, the ring's 3D models and board, and the plans. The full history comes with it. Notes that aren't code (memory, company knowledge, health and location data) stay in your Cloudflare database, never in the repo. Making the repo public can't be undone: once people or search engines copy it, deleting it doesn't remove those copies.
  ```text
  RelayEverything/        public, MIT
  ├── app/       server, private site
  ├── mobile/    phone app (was relay-app)
  ├── site/      relayeverything.com
  ├── cad/ pcb/  the ring
  ├── vendor/    parts library (own license)
  └── openspec/ wiki/   plans, how we work

  Stays in Cloudflare:
    memory, knowledge, notes,
    health, location, keys
  ```
- **Nothing private goes public, past or future.** Before the repo opens, a scan reads every file in every past commit for keys, values from your private settings, Apple key files and private notes. Any hit stops the move and names the file and commit, never the value. You decide on each hit before anything is public. After the move, the same check runs on every change, so a key in a pull request fails its checks.
  ```mermaid
  flowchart TD
    A["Scan every past commit"] -->|"clean"| B["Push full history to GitHub (private)"]
    A -->|"hit"| C["Stop: file and commit named"]
    C --> D["You decide: remove it from history, or it is safe"]
    D --> A
    B --> E["Checks pass on GitHub"]
    E --> F["You say yes"]
    F --> G["Repo made public"]
  ```
- **MIT license.** A `LICENSE` file at the top says anyone may use, change and share the code. The Nordic parts library keeps its own license, and a short README says what Relay is, links to relayeverything.com and says how to run it.
- **GitHub runs the checks.** Every save opens a pull request on GitHub, and GitHub Actions runs the same checks the Cloudflare check runner runs today: tests, wiki links, the guard and the preview. People outside can open pull requests too. Their checks run without any of your keys and never deploy. Publishing a change merges its pull request, and the merge deploys your live site as today.
  | | Today | After |
  |---|---|---|
  | Where the project lives | Cloudflare (private) | GitHub (public) |
  | Who runs the checks | Cloudflare check runner | GitHub Actions |
  | A change is reviewed as | the plan's page and a preview | the same, plus a pull request |
  | Outside contributors | none | pull requests, with no keys and no deploy |
- **The phone app moves in.** The iPhone and Android builds run in RelayEverything on each change to the phone app. The Android file is released there, and the website's *Android app* and *The app's code* links point there. relay-app gets a note that says it moved, and becomes read-only. The copy step after each publish goes away.
  ```mermaid
  flowchart TD
    A["Change to mobile/"] --> B["Pull request"]
    B --> C["Flutter tests"]
    C --> D["Android file kept"]
    C --> E["TestFlight, with Apple keys"]
    B -->|"merge"| F["main"]
    F --> G["Android release"]
  ```
- **The other chats switch over.** After the publish, each open Relay chat saves to GitHub. Their unpublished work moves with its branch, and nothing is lost. The Cloudflare names (relay-ring Worker, database, storage) stay for now: the rename and the data move are planned in "Rename Relay to RelayEverything in Cloudflare".

## What the build needs

- **GitHub login**: Ready. This computer is signed in as matthewwong525, with rights to make repos, set secrets and archive.
- **Cloudflare token for GitHub's deploys**: Ready. The build makes a new narrow deploy token with the Cloudflare token in `.env`, the same rights as today's. If Cloudflare refuses, the build stops and asks.
- **Apple keys for TestFlight**: Ready, not needed for this build. iPhone builds skip until you pay for the Apple Developer Program and add the keys.

## Capabilities

### New Capabilities
- `relay-open-source`: the public GitHub repo, its license, the history scan before it opens, the check on each change that keeps keys and private notes out, and GitHub Actions as the gate, safe for outside pull requests.

### Modified Capabilities
- `relay-app-builds`: phone builds run in RelayEverything on changes to `mobile/`, and releases are made there, not in relay-app.
- `relay-app-publish`: retired. The copy to relay-app ends; its key guard becomes the repo-wide check in `relay-open-source`.

## Impact

- New GitHub repo `matthewwong525/RelayEverything` (public after the scan), with `origin` moved from the Cloudflare Artifacts repo `wongstack/relay-ring`. `.agents/.wong-stack.json` loses `components.delivery`, so the skills take the GitHub route (`delivery-route.mjs`).
- GitHub secrets: `CLOUDFLARE_DEPLOY_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, and later the App Store Connect four (`ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`). Branch rules on `main` require the `test` check.
- `app/wrangler.jsonc`: `WONG_CODE_REPOSITORY` becomes `matthewwong525/RelayEverything`, with a read-only GitHub token secret for the app's code reader. `CODE_CHECKS` and the `relay-ring-checks` runner Worker stop being used.
- `mobile/.github/workflows/*` move to `.github/workflows/mobile-*.yml`, scoped to `mobile/`.
- Removed: `scripts/publish-relay-app.mjs` and its test; the relay-app rules in `AGENTS.md`; the relay-app lines in `.env.example`. Its guard moves to `scripts/public-check.mjs`.
- New: `LICENSE`, `README.md`, `scripts/public-check.mjs` and its test, a `public-check` step in CI.
- `site/`: links to relay-app change to RelayEverything; the ring pages may link to `cad/` and `pcb/`.
- relay-app on GitHub: a pointer README, then archived (read-only). Archiving can be undone in GitHub's settings.
- Every open worktree: `origin` changes to GitHub (`git remote set-url`).

## Decision log

The plan's decisions are in [design.md](design.md#decision-log); this log holds only the checks the build changed.

- **2026-11-05** — Check: `.github/workflows/test.yml` gains a step that runs `scripts/public-check.mjs --tree` on every change, docs included, because the repository is public; no check is loosened.
- **2026-11-05** — Check: `.github/workflows/mobile-ci.yml`, `.github/workflows/mobile-android.yml` and `.github/workflows/mobile-ios.yml` are relay-app's phone workflows moved in, scoped to `mobile/`, because the phone app now builds in this repository; a fork's pull request runs the Flutter tests only, with no secret.
- **2026-11-05** — Check: `scripts/publish-relay-app.test.mjs` is deleted with `scripts/publish-relay-app.mjs`, because the copy to relay-app ends; its guard cases move to `scripts/public-check.test.mjs`, which `npm test` in `app/` now runs.
- **2026-11-05** — Check: `app/package.json` adds `public-check.mjs --tree` and its own tests to `npm test`, so the check before a save also reads this computer's `.env` values; no check is loosened.
