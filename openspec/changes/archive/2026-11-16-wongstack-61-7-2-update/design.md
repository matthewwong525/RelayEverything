# Design

## Context

The install record (`.claude/.wong-stack.json`) says 61.7.0 at commit `ea0af925`. The source checkout at `/root/.cache/wong-stack/WongStack` is at 61.7.2, commit `1c4c6663`, refreshed on 2026-11-16. Its two commits since `ea0af925` are 61.7.1 (PR #604, the ✅ drawing) and 61.7.2 (PR #605, pop-ups and the toolbar fit a phone's live view).

The preflight reports `status: update`, 774 units, 5 changed, `updatingComplete: true`, no diagnostics.

## The changed parts

All five are `modified` upstream and `installed-equivalent` here, so each copies whole with `node <source>/.claude/skills/wong-sync/scripts/install-path.mjs --source <source> <sourcePath> > <targetPath>`:

| Source path | Target path |
|---|---|
| `.claude/plugins/browser/VERSION` | `.claude/skills/browser/VERSION` |
| `.claude/plugins/browser/addon/check.svg` | `.claude/skills/browser/addon/check.svg` |
| `.claude/plugins/browser/references/password-manager.md` | `.claude/skills/browser/references/password-manager.md` |
| `.claude/plugins/browser/skills/hand-over/scripts/view-page.mjs` | `.claude/skills/browser/skills/hand-over/scripts/view-page.mjs` |
| `.claude/plugins/browser/skills/hand-over/scripts/view.mjs` | `.claude/skills/browser/skills/hand-over/scripts/view.mjs` |

No merge by hand. Both `updating` notes say *Nothing to do by hand*.

## Catch-up

`catchUp` names `module-plugin` for `.claude-plugin/marketplace.json` only. That file lists one plugin, `relay` from `./plugin`: Relay Everything's public plugin list, so it stays. `.claude/settings*.json` has no `enabledPlugins` key, so the move has nothing else to do.

## Checks

The browser's own tests, if the source ships any for the hand-over view, run from the source. Here, run the merge check, the public check, the product-name test and `.github/scripts/checks.mjs`'s wiki and payload link checks.
