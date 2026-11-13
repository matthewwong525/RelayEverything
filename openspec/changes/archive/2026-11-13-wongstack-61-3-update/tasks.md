# Tasks

## 1. Copy WongStack 61.3.0

- [x] 1.1 Rerun the preflight to `.scratch/wong-preflight.json` (design §Context) and confirm 23 changed units at commit `102e1abb`, none `locally-adapted`. Copy every unit by `install-path.mjs` to its `targetPath`, making `.claude/skills/browser/addon/` first. Verify: each of the 23 files equals `install-path.mjs` output, and `git status` shows no other changed file except this change's folder.

## 2. Check

- [x] 2.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target <this checkout> --source /root/.cache/wong-stack/WongStack --from 9d63c758a4d72c8ce199865ed1ba26f5d7253ad7`. Verify: exit 0, `status: clean`.
- [x] 2.2 Run `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs`, and the wiki and payload link checks `.github/scripts/checks.mjs` runs. Verify: all pass.
- [x] 2.3 Run `node .claude/loop/step-title.mjs` through the hook path the settings use, by starting a fresh Claude Code chat in this checkout (`claude -p` with a one-word prompt). Verify: it exits with no error and the memory start line prints once.
- [x] 2.4 Rebuild this plan's page with the builder (`build-review.mjs <change-root> --require-current`). Verify: it builds with no warning.

## 3. Record and save

- [x] 3.1 Set `version` to `61.3.0` and `commit` to `102e1abbe5d7b156d067431b4e166f5c5bb768db` in `.claude/.wong-stack.json`, keeping every other key. Then run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/codex-plugin.mjs` in this checkout. Verify: the preflight run again reports `status: current`, and the Codex helper prints that nothing was removed.
- [x] 3.2 `/save`, then wait for CI on the pull request. Verify: every check passes.
