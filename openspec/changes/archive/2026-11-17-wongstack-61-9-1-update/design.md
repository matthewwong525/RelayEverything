# Design

## Context

The install record (`.claude/.wong-stack.json`) says 61.7.2 at commit `1c4c6663`. The source checkout at `/root/WongStack` is at 61.9.1, commit `88730bba`, fetched on 2026-11-17. Its three commits since `1c4c6663` are 61.8.0 (PR #606, the key link), 61.9.0 (PR #608, a plan's screens as pages) and 61.9.1 (PR #609, `finish --done`).

The preflight reports `status: update`, 774 units, 21 changed, `updatingComplete: true`, no diagnostics.

## The changed parts

Copy each `installed-equivalent` and `latest-equivalent` unit whole with `node /root/WongStack/.claude/skills/wong-sync/scripts/install-path.mjs --source /root/WongStack <sourcePath> > <targetPath>`:

| Source path | Target path |
|---|---|
| `.claude/inbox/schedules.mjs` | `.claude/inbox/schedules.mjs` |
| `.claude/plugins/loop/skills/apply/SKILL.md` | `.claude/skills/apply/SKILL.md` |
| `.claude/plugins/loop/skills/apply/references/build-helper.md` | `.claude/skills/apply/references/build-helper.md` |
| `.claude/plugins/browser/VERSION` | `.claude/skills/browser/VERSION` |
| `.claude/plugins/browser/skills/hand-over/references/key-link.md` | `.claude/skills/browser/skills/hand-over/references/key-link.md` |
| `.claude/plugins/browser/skills/hand-over/scripts/keys-page.mjs` | `.claude/skills/browser/skills/hand-over/scripts/keys-page.mjs` |
| `.claude/plugins/browser/skills/hand-over/scripts/keys.mjs` | `.claude/skills/browser/skills/hand-over/scripts/keys.mjs` |
| `.claude/plugins/daily/VERSION` | `.claude/skills/daily/VERSION` |
| `.claude/plugins/daily/skills/schedule/references/run.md` | `.claude/skills/daily/skills/schedule/references/run.md` |
| `.claude/plugins/daily/skills/schedule/scripts/lib/hosts.mjs` | `.claude/skills/daily/skills/schedule/scripts/lib/hosts.mjs` |
| `.claude/plugins/loop/VERSION` | `.claude/skills/loop/VERSION` |
| `.claude/plugins/loop/skills/plan/references/prototypes.md` | `.claude/skills/plan/references/prototypes.md` |
| `.claude/plugins/loop/skills/plan/references/review-kit.html` | `.claude/skills/plan/references/review-kit.html` |
| `.claude/plugins/loop/skills/plan/references/review-page.md` | `.claude/skills/plan/references/review-page.md` |
| `.claude/plugins/loop/skills/plan/scripts/build-review.mjs` | `.claude/skills/plan/scripts/build-review.mjs` |
| `.claude/plugins/loop/skills/plan/scripts/look.mjs` | `.claude/skills/plan/scripts/look.mjs` |
| `wiki/prototypes.md` | `wiki/prototypes.md` |

Delete `.claude/skills/plan/scripts/prototype.mjs` (removed upstream, `installed-equivalent` here).

## The merged parts

Each `locally-adapted` file starts from `install-path.mjs` output, then gets its local lines back:

- `.claude/skills/plan/references/drawings.md`: keep the local sub-bullet under the `live` fence (*Open its page in a browser before you build…*).
- `wiki/ux-principles.md`: keep *Relay Everything's own palette, type and screen rules are on [the brand page](brand.md).* in the Principles lead.
- `wiki/review-pages.md`: take the source whole. The local *A phone app screen gets its pictures from a screen test* line goes, by 61.9.0's note.

## 61.9.0's target impact

61.9.0 says a repo's own screen test steps for plan pictures are no longer read. Here they are wired in four places:

- `.agents/skills/plan/SKILL.md`: drop the local clause *a phone app screen gets its pictures from its screen test*, matching the source.
- `.agents/rules/mobile.md`: the first rule line says a plan that changes a phone screen writes it as a page in the phone app's look ([another app's look](../../../../wiki/prototypes.md#another-apps-look)), not a screen test picture.
- `wiki/development/phone-pictures.md`: keep the steps, for your own checks only. Its first paragraph says plans use pages now; step 6 and the `No real picture` paragraph go, since a plan no longer reads them.
- Links to old headings of `wiki/prototypes.md` (`#a-web-app`, `#an-app-the-preview-cant-serve`) exist only inside the files that this update replaces.

## Catch-up

`catchUp` names `module-plugin` for `.claude-plugin/marketplace.json` only. That file lists one plugin, `relay` from `./plugin`: Relay Everything's public plugin list, so it stays. `.claude/settings*.json` has no `enabledPlugins` key.

## Checks

`node --check` on each copied script, the merge check, `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs`, and `.github/scripts/checks.mjs`'s wiki and payload link checks. The plan page itself rebuilds with the new `build-review.mjs`.

## After publish

The background helper loads the schedule code, so reinstall it in `/root/relay-ring` after `main` syncs, at a minute not ending in 0 or 5 ([WongStack updates](../../../../wiki/development/wongstack-updates.md)).
