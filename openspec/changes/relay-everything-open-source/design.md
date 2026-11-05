# Design

## Context

The project lives in a private Cloudflare Artifacts repo (`wongstack/relay-ring`), checked by the `relay-ring-checks` runner Worker ([the Artifacts route](../../../wiki/stack/artifacts-route.md)). Only `mobile/` is public, copied after each publish to `matthewwong525/relay-app` by `scripts/publish-relay-app.mjs`, which also runs that repo's Flutter, Android and iOS workflows. No file in either repo has a license. History is 12 commits, all by one author.

WongStack already supports the [GitHub route](../../../wiki/stack/github-actions.md): `delivery-route.mjs` picks `github` when `origin` is not an Artifacts host and `.agents/.wong-stack.json` has no `components.delivery`. The shipped `.github/workflows/` (`test.yml`, `deploy.yml`, `guard.yml`) run there, and are safe for fork pull requests (deploy secrets only on pushes; `guard.yml` reads the PR as text only).

## Goals / Non-Goals

Goals: one public, MIT-licensed monorepo on GitHub with its full history; nothing private in it, past or future; GitHub Actions as the gate; phone builds and releases from the monorepo; relay-app retired.

Non-goals: renaming the Cloudflare Worker, databases, buckets, Access apps or the private site's address (planned in "Rename Relay to RelayEverything in Cloudflare"); moving the website's deploy into CI; the app's GitHub code-reader key (`WONG_CODE_READ`, needed only to hand the code to teammates through the app); self-hosting docs.

## Decisions

### Switch the delivery route, keep everything in Cloudflare that isn't code

Create `matthewwong525/RelayEverything` **private** first, push all branches and tags, then remove `components.delivery` from `.agents/.wong-stack.json` and set `origin` to GitHub. `components.knowledge` (`relay-ring-knowledge`), the memory D1 and R2, and the live app's data stay where they are: non-code notes live there by design. `WONG_CODE_REPOSITORY` becomes `matthewwong525/RelayEverything`; with no read key the app's code reader shows its "key" step, which is fine for a team of one. The `ARTIFACTS` and `CODE_CHECKS` bindings and the runner Worker stay deployed but unused until the rename change removes them, so a rollback is a `git remote set-url` and a revert.

### The repo goes public only after the scan and a green run

Order: scan history → push to the private GitHub repo → secrets and branch rules → this change's own pull request passes there → the person says yes → `gh repo edit --visibility public`. The visibility flip is the one step that can't be undone, so it is the last one and waits for an explicit yes, even inside `/ship`.

### One public check, three uses

`scripts/publish-relay-app.mjs` already holds the guard: secret-shaped files (`.p8`, `.p12`, `.cer`, `.mobileprovision`, `.env*` but `.env.example`), key-shaped text, and `.env` values. It moves to `scripts/public-check.mjs` with three modes:

- `--tree` (default): every tracked file at `HEAD`. CI runs it in the Test job; `.env` values are checked only where `.env` exists, so CI uses the shapes and the save on this computer adds the values.
- `--history`: every blob reachable from any ref (`git rev-list --objects --all`), reporting `commit:path`, never the value.
- `--notes`: a list, for a person to read, of every non-code file in history (`openspec/`, `wiki/`, `*.md`) with any line naming health or location values, phone numbers, street addresses or emails other than the author's commit email. It flags; it never fails alone.

A hit prints `result=refused <commit>:<path> <kind>`; clean prints `result=clean`. Removing a hit from history (`git filter-repo`) rewrites every commit id, so it waits for the person's decision on that hit.

The author's commit email (`matthewwong525@gmail.com`) and the IDs in `.agents/.wong-stack.json` and `app/wrangler.jsonc` (account, Access app, audience, database ids) are not secrets: Access still guards every route. The website's own guard keeps refusing the private site's address in pages.

### Phone workflows move to the root

`mobile/.github/workflows/{ci,android,ios}.yml` become `.github/workflows/mobile-{ci,android,ios}.yml` with `defaults.run.working-directory: mobile` and `paths: ['mobile/**', '.github/workflows/mobile-*.yml']`. Android releases are created in RelayEverything with tag `mobile-v<pubspec version>`; `site/` links to `releases/latest` change to the new repo. iOS keeps skipping until the four App Store Connect secrets are set. The Android keystore secrets were never set in relay-app, so nothing moves.

### relay-app is archived, not deleted

Its README is replaced with one paragraph pointing to `RelayEverything/mobile` and the new releases page, then `gh repo archive`. Old releases stay downloadable. Archiving can be undone in settings; deleting can't, so it isn't done.

### License and README

`LICENSE` is MIT, `Copyright (c) 2026 Matthew Wong`, covering the whole repo except `vendor/`, whose libraries keep their own files (`nordic-lib-kicad` is CERN-OHL-P-2.0, which allows this). `README.md` says what Relay is in the website's words, links relayeverything.com and its *Get started*, lists the folders, and says how to run the checks.

### Other worktrees

After the publish, each open worktree's `origin` is set to GitHub. Unpublished branches still exist on the Artifacts remote; each is pushed to GitHub by its own next `/save`, which follows the new route. The open chats get one message saying so.

## Risks / Trade-offs

- **A secret in history goes public** → the scan runs on every blob before any push, and the flip waits for a yes.
- **A private note in a plan goes public** → `--notes` gives the person a list to read before the flip; plans and decision logs are already written for teammates to read.
- **CI differs from the check runner** → this change's own pull request must pass on GitHub before the flip; a failure is fixed in this change.
- **Fork pull requests reach secrets** → the shipped workflows pass no secret to them; `scripts/tests/guard-workflow.test.mjs` already guards the one `pull_request_target` workflow.
- **Another chat publishes to Artifacts mid-move** → the switch happens in one step at publish; the move pushes `main` again right before the flip, and any later Artifacts push is refused because `origin` changed.

## Migration Plan

1. Scan history; stop on any hit.
2. Create the private repo, push all refs, set secrets and branch rules, switch the route in this branch.
3. Save: this change's pull request runs on GitHub.
4. `/ship` merges and confirms `main`'s run deploys the live site and makes an Android release. These steps follow the merge, in the shipping chat, so they are not tasks (the archive needs every task ticked):
   1. Run `public-check.mjs --history` again on `main`; with the person's yes, make the repo public.
   2. Replace relay-app's README with the pointer note, then archive it.
   3. Set `origin` to GitHub in every open worktree; message each open Relay chat that saves now go to GitHub and that unpublished branches push on their next `/save`.

Rollback before the flip: set `origin` back to the Artifacts remote, restore `components.delivery`, delete the private GitHub repo.

## Decision log

- **2026-11-05** — Asked what may be deleted to free the full disk → chose old /tmp folders untouched for 2 days.
- **2026-11-05** — Asked what happens to history when the repo goes public → chose keep it, after a scan.
- **2026-11-05** — Asked what happens to relay-app → chose fold it in (builds in the monorepo, relay-app archived, copy script removed).
- **2026-11-05** — Asked what gets the new name → chose everything, Cloudflare included.
- **2026-11-05** — Asked which license → chose MIT.
- **2026-11-05** — Asked how to split the work → chose two parts: this GitHub move here, the Cloudflare rename in workspace "Rename Relay to RelayEverything in Cloudflare".
- **2026-11-05** — Asked when the move happens → chose GitHub now, the rename after the MCP and offline-notes builds are live.
- **2026-11-05** — Asked where the private site lives after the rename → chose app.relayeverything.com (in the rename part).
- **2026-11-05** — Assumed: the repo is named `RelayEverything` under `matthewwong525`, because that is the name asked for and it is free.
- **2026-11-05** — Assumed: MIT covers `cad/` and `pcb/` too, because the person asked for one license for everything; `vendor/` keeps its own.
- **2026-11-05** — Assumed: the website keeps deploying from this computer after each publish, because its deploy needs the custom-domain rights the narrow CI token lacks; moving it to CI can be its own change.
- **2026-11-05** — Assumed: the app's GitHub code-reader key is left out, because only teammates use it and Matthew works alone.
- **2026-11-05** — Assumed: the old Artifacts repo and check runner stay until the rename change, because that keeps a rollback.
- **2026-11-05** — Assumed: an Android release's tag is `mobile-v<pubspec version>+<run number>`, such as `mobile-v1.0.0+42`, because the build number already comes from the run and a tag of the version alone would clash on the second publish.
- **2026-11-05** — Assumed: the public check also refuses `.dev.vars` files and the values in `app/.dev.vars`, and a few more key shapes (Google, Stripe, `wongm_`), because they are private in the same way as `.env`; `CLOUDFLARE_ACCOUNT_ID` is the one `.env` value it lets through, as an ID, not a key.
- **2026-11-05** — Assumed: `--tree` reads the files on disk, untracked ones included, not only `HEAD`, so the check before a save sees what the save adds; in CI the two are the same.
- **2026-11-05** — Assumed: `--notes` skips `vendor/` (its makers' public text) and email addresses at example domains or no-reply senders, because none of them is a person's private detail.
- **2026-11-05** — Assumed: the mobile workflows' first job is named `flutter`, not `test`, so the branch rule's required `test` check names only the Test workflow.
- **2026-11-05** — The history scan (`--history`, every ref) found nothing: `result=clean`.
- **2026-11-05** — Listed for review: `--notes` found 7 lines, all in two WongStack wiki pages from the first setup commit (`wiki/development/passwords.md` line 22: an email; `wiki/development/private-form.md` lines 85, 88 and 96: an email and a street address each). They read as made-up examples. Waiting for Matthew's answer before the repository is made public.
- **2026-11-05** — Assumed: this worktree's `origin` points to GitHub through its own worktree config (`extensions.worktreeConfig`), not `git remote set-url`, because that would move every other open worktree too; they move after the publish.
- **2026-11-05** — The CI deploy token is `RelayEverything-deploy`, with the same rights as `relay-ring-deploy`; `relay-ring-deploy` stays for the check runner until the rename change.
- **2026-11-05** — Assumed: the 7 `--notes` lines are safe to publish, because they are WongStack's own placeholder examples (`me@x.com`, `1 Main St`), already public in the WongStack repo; Matthew still gives the yes before the repo goes public.
- **2026-11-05** — Save for task 5.1: the review's three fixes are in (LICENSE is the plain MIT text so GitHub detects it, the release tag reads `mobile-v<version>+<build>` everywhere, and a test proves `--tree` reads new uncommitted files and `app/.dev.vars` values); the first pull request runs on GitHub Actions.
