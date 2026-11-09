# Tasks

## 1. Copy the unchanged-locally units

- [x] 1.1 Copy the 12 installed-equivalent files listed in the design from `/root/WongStack` to this repo; verify each target blob equals the source blob (`git hash-object` compare).

## 2. Take and merge the locally-adapted units

- [x] 2.1 Take upstream's text for the 9 close-rule units in the design: the `WONG-STACK` block in `AGENTS.md` (only between its markers), and the 8 files whole; verify each equals the source (block compare for `AGENTS.md`), and `AGENTS.md` keeps every line outside the block.
- [x] 2.2 Merge `wiki/development/browsing.md` and `wiki/development/daily.md` by the design; verify the upstream sentences are present, `## When your turn holds the browser` and the `ship-every-chat.md` line are kept, and each page stays under 3,000 words.
- [x] 2.3 Take `wiki/review-pages.md` and `wiki/ux-principles.md` from the source, then put back each local line by the design (the review-pages tip goes to `drawings.md`, by the Decision log); verify `diff` against the source shows only those lines.

## 3. Check

- [x] 3.1 Run `node /root/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target /root/.paseo/worktrees/11511sre/famous-goose --source /root/WongStack --from 3ee8c0f97091af2831f42120d889babfd9a62759`; take every missing hunk, or name each one dropped on purpose (the old local close wording), until no other remains.
- [x] 3.2 Rebuild this change's page with the new builder (`build-review.mjs openspec/changes/wongstack-51-7-update --require-current`); verify it builds with no error.
- [x] 3.3 Run `npm test` in `app/` and `node scripts/public-check.mjs --tree`; verify all pass, `tidy.test.mjs` included, with no check loosened.
- [x] 3.4 Run `/save`; verify the pull request's checks pass.

## 4. Install record

- [x] 4.1 Set `.claude/.wong-stack.json` `version` to `51.7.0` and `commit` to `a8a601a0b48dd724d48ebaf7ec0808891f7c56e2`, keeping every other key; verify the JSON parses and the preflight reports `current`, or only the 4 merged pages as `locally-adapted`.
