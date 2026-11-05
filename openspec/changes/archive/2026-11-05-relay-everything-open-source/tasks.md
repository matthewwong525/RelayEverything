# Tasks

## 1. Public check (scripts/)

- [x] 1.1 Move the guard from `scripts/publish-relay-app.mjs` into `scripts/public-check.mjs` with `--tree`, `--history` and `--notes` modes and one `result=` line, as in design.md; never print a matched value
- [x] 1.2 Write `scripts/public-check.test.mjs` (node:test) on a temporary git repo: a key-shaped string, a `.p8` file and a `.env` value each refuse with `commit:path`; a key removed by a later commit is still found by `--history`; `.env.example` and the author's commit email pass; `--notes` lists a phone number without failing
- [x] 1.3 Delete `scripts/publish-relay-app.mjs` and its test; run the public check in CI's Test job (`--tree`) and in the root `npm test`

## 2. Repo files

- [x] 2.1 Add `LICENSE` (MIT, Copyright (c) 2026 Matthew Wong, `vendor/` excluded) and `README.md` (what Relay is, relayeverything.com, folders, how to run the checks)
- [x] 2.2 Move `mobile/.github/workflows/*` to `.github/workflows/mobile-{ci,android,ios}.yml`, scoped to `mobile/` by `paths` and `working-directory`; Android releases tagged `mobile-v<version>` on this repo
- [x] 2.3 Update `AGENTS.md` (drop the relay-app publish and pre-publish build rules; say phone builds run on each pull request), `.env.example` (drop relay-app lines), `mobile/README.md`, `wiki/relay-website.md` and every `site/` link to relay-app; let the ring pages link to `cad/` and `pcb/` on GitHub
- [x] 2.4 Remove `components.delivery` from `.agents/.wong-stack.json`; set `WONG_CODE_REPOSITORY` to `matthewwong525/RelayEverything` in `app/wrangler.jsonc` (both environments) and regenerate `app/worker-configuration.d.ts`

## 3. History scan (outward steps wait here)

- [x] 3.1 Run `public-check.mjs --history` on all refs; on any hit, stop and report `commit:path` and kind to the person, building nothing further
- [x] 3.2 Run `public-check.mjs --notes` and give the person its list to read; record their answer in the Decision log

## 4. GitHub (private until 6.2)

- [x] 4.1 Create `matthewwong525/RelayEverything` as **private**; push all branches and tags from the Artifacts remote; set `origin` to GitHub in this worktree
- [x] 4.2 Make a narrow Cloudflare deploy token matching `relay-ring-deploy`'s rights; set GitHub secrets `CLOUDFLARE_DEPLOY_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`; add a `main` rule that requires the `test` check
- [x] 4.3 Run `checks.mjs --worktree` and fix what fails

## 5. Verify

- [x] 5.1 `/save`: this change's pull request runs on GitHub Actions; the Test, Guard, mobile CI and preview deploy pass; the preview link opens behind the login
- [x] 5.2 Open a pull request from a fork-like branch without secrets (or read the run's settings) and confirm no deploy job ran with secrets
