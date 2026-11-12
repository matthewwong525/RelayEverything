# Tasks

## 1. Copy and remove WongStack 55.2.1

- [x] 1.1 Rerun the preflight from `/root/.cache/wong-stack/WongStack` (design §Context) and confirm 635 changed units at commit `a282a4a9`. Copy every `installed-equivalent` and `missing` unit with `added` or `modified` by `install-path.mjs` to its `targetPath`, including the `WONG-STACK` block into `AGENTS.md`. Verify: for a sample of 20 units across the five modules, the target equals `install-path.mjs` output; `git status` shows no file outside the preflight's list except the planned edits.
- [x] 1.2 `git rm` every `removed` / `installed-equivalent` unit, and remove empty folders it leaves (`.claude/skills/dream-memory/`, `.claude/skills/services/`, `.claude/skills/memory/{worker,migrations}/`). Verify: none of the 153 paths exists.
- [x] 1.3 Remove the `codex-plugin.mjs --check` hook entry from `.agents/hooks.json`, keeping the rest of the copied file. Verify: `node -e 'JSON.parse(...)'` parses it and no line names `codex-plugin.mjs`.

## 2. Merge local edits and repoint Relay Everything code

- [x] 2.1 Merge the plan tool files, `paseo.json`, `schema/seed.sql`, `scripts/seal-keys.mjs` and the four wiki pages in design §Merge list. Verify: `diff` against the source for each shows only local lines.
- [x] 2.2 Merge the app files in design §Merge list: `app/worker/index.ts`, `app/worker/apps/index.ts`, `app/worker/api/contract.ts`, the Vite, Vitest and Knip configs, `app/package.json` (service-records check at `../.claude/skills/access/scripts/check-definitions.mjs`), and the seven test files. Verify: every Relay Everything route and test case in the old files is still present.
- [x] 2.3 Point `app/worker/relay-only.ts`, `app/worker/relay-only.test.ts`, `app/tests/relay.ts` and `app/worker/apps/relay/sign-in/{access,connect}.test.ts` at `app/worker/access-slots.ts`. Verify: `grep` finds no import of `worker/access.ts` or `./access"` in `app/`.
- [x] 2.4 Move the *Relay devices* machine-policy case from the removed `login-management.test.ts` into the Access module's test of the login policy. Verify: the case runs and fails when the extra policy is allowed.
- [x] 2.5 Point `wiki/development/README.md`'s eight browser-guide links at their new places (53.3.0's note) and drop `memory-extraction.md`. Verify: the repo's wiki link check passes.
- [x] 2.6 On `knowledge/people/matthew-wong.md`: point *Another chat's live view* at the browser window guide's turn section, and add *keep the home proxy setting on, on Matthew's computers*. Save it through the company knowledge save. Verify: the save prints its commit and the page shows both lines.

## 3. Check

- [x] 3.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target /root/.paseo/worktrees/11511sre/shallow-dragon --source /root/.cache/wong-stack/WongStack --from 16a0af7ed5b6a02c1f629e2bc0b06e1c58e9fb21`. Verify: exit 0, or each missing hunk is taken or named in the Decision log.
- [x] 3.2 Run `npm test` in `app/`, `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs`, and the wiki and payload link checks the repo's CI runs. Verify: all pass.
- [x] 3.3 Start a fresh Claude Code chat in this checkout (`claude -p` with a one-word prompt). Verify: the memory start hook runs from the module folder (it prints the topics, or says the store waits for production's route). The digest itself and the *files behind these facts* list are checked after the deploy (design §Migration Plan step 3).
- [x] 3.4 Rebuild this plan's page with the copied builder (`build-review.mjs <change-root> --require-current`). Verify: it builds with no warning.

## 4. Record and publish

- [x] 4.1 Set `version` to `55.2.1` and `commit` to `a282a4a936bc3b02b671682822bacfe82c255be1` in `.claude/.wong-stack.json`; in `components.skills` drop `dream-memory` and `services`, add `reply-link` and `access`, and keep every other key. Verify: the preflight run again reports `status: current`.
- [ ] 4.2 `/save`, then wait for CI on the pull request. Verify: every check passes.
