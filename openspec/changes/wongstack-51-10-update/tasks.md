# Tasks

## 1. Copy and merge WongStack 51.10.0

- [x] 1.1 Copy the 19 installed-equivalent files listed in design.md from `/root/.cache/wong-stack/WongStack` (source `.agents/…`) to the target (`.claude/…`, `app/…`, `wiki/…`). Verify: `git diff --stat` shows those 19 files and `cmp` against each source file passes.
- [x] 1.2 Merge `.claude/skills/plan/references/drawings.md`: take source lines 10-11, keep the local *open its page in a browser* tip under the `live` line. Verify: the tip is still there and `diff` against the source shows only that tip.
- [x] 1.3 Merge `wiki/ux-principles.md`: take *Close stands alone* and the new preview-page paragraph, keep the brand-page sentence. Verify: `diff` against the source shows only the brand-page sentence.
- [x] 1.4 Check for scheduled chats that are still open: list Paseo agents whose workspace or title comes from a schedule. Verify: the build report names each one, or says none, for 51.10.0's note.

## 2. Check

- [x] 2.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target /root/.paseo/worktrees/11511sre/peachy-snake --source /root/.cache/wong-stack/WongStack --from a8a601a0b48dd724d48ebaf7ec0808891f7c56e2`. Verify: `status` is `ok`, or each missing hunk is taken or named in the Decision log.
- [x] 2.2 Run the local checks: `npm test` in `app/` (inbox cadence test included), `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs`, and the wiki and payload link checks the repo's CI runs. Verify: all pass.
- [x] 2.3 Rebuild this plan's page with the copied builder (`build-review.mjs <change-root> --require-current`). Verify: it builds with no warning about a question in a card.

## 3. Record and publish

- [x] 3.1 Set `version` to `51.10.0` and `commit` to `16a0af7ed5b6a02c1f629e2bc0b06e1c58e9fb21` in `.claude/.wong-stack.json`, keeping every other key. Verify: the preflight run again reports `status: current`.
- [ ] 3.2 `/save`, then wait for CI on the pull request. Verify: every check passes.
