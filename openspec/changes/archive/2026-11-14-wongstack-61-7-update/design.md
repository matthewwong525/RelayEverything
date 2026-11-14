# Design

## Context

The install record (`.claude/.wong-stack.json`) says 61.5.0 at commit `a43bb2af`. The source checkout at `/root/.cache/wong-stack/WongStack` is at 61.7.0, commit `ea0af925`, refreshed on 2026-11-14. Its two commits since `a43bb2af` are 61.6.0 (PR #601, `/ui`, the design guide, the starter look) and 61.7.0 (PR #603, the green check).

The preflight reports `status: update`, 774 units, 29 changed, `updatingComplete: true`. Rerun it at build time into a file only this chat uses:

```bash
mkdir -p .scratch
node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/preflight.mjs \
  --target <this checkout> --source /root/.cache/wong-stack/WongStack \
  --record .claude/.wong-stack.json > .scratch/wong-preflight.json
```

Copy each unit with `node <source>/.claude/skills/wong-sync/scripts/install-path.mjs --source <source> <sourcePath> > <targetPath>`.

## The changed parts

**Copy whole** (`installed-equivalent` or `added`/`missing`):

- **Browser** (`.claude/skills/browser/`, 61.7.0): `SKILL.md`, `VERSION`, `addon/background.js`, `addon/manifest.json`, `addon/check.svg` (new), references `browser-window.md`, `browsing.md`, `password-manager.md`, `scripts/addons.mjs`, `skills/hand-over/references/live-view.md`, `skills/hand-over/scripts/hand-over.mjs`; `.claude/skills/hand-over/SKILL.md`.
- **Remove**: `.claude/skills/browser/addon/bell.svg`.
- **Loop / plan**: `.claude/skills/loop/VERSION`, `.claude/skills/plan/references/look.css`, `review-kit.html`.
- **ui**: `.claude/skills/ui/SKILL.md` (new); `wiki/design-guide.md` (new, verbatim).
- **wong-sync**: `references/payload-files.json`, `references/payload-manifest.md`.
- **Rules and checks**: `.claude/rules/code.md`, `app/.oxlintrc.json`, `app/src/style.test.ts`, `scripts/check-app-checks.mjs`.
- **Look**: `app/src/index.css`, copied, then the accent set as below.

**Merge by hand** (`locally-adapted`; add upstream's new lines, keep local text):

- `.claude/memory/areas.json`: add the `ui` area after `review`, with `.claude/` paths as this install writes them.
- `.claude/skills/plan/SKILL.md`: the `## UX` line loads `/ui`; *return the exact change name.*
- `wiki/stack/mini-apps.md`: the two look paragraphs, *one accent colour*, the brand list and the design-guide link.
- `wiki/ux-principles.md`: the first paragraph names the design guide beside the code rule.

Plus `wiki/README.md`: add `[design guide](design-guide.md)` after UX principles in the wiki list, so the new page has a parent.

## The accent

`app/src/index.css` takes upstream's file, then sets the brand's Emerald accent from [`wiki/brand.md`](../../../wiki/brand.md#colors), in hex, which the readable-colour check reads:

| Value | `:root` | `.dark` |
|---|---|---|
| `--primary` | `#0E7A5A` | `#4CC79A` |
| `--primary-foreground` | `#FFFFFF` | `#06281A` |
| `--ring` | `#0E7A5A` | `#4CC79A` |

White on `#0E7A5A` is about 5.4 to 1; `#06281A` on `#4CC79A` is about 8 to 1. Both pass 4.5. The rest of the list (greys, `--font: system-ui`, `--radius`, three shadows) stays upstream's. `style.test.ts`'s own samples replace `--primary` with fixed values, so the brand accent changes no expected result.

`wiki/brand.md`'s *one home per surface* line gains the admin app: `app/src/index.css`, the accent only, read also by the plan review page and the private pages. It is a fifth place to change with the accent.

## Catch-up

The preflight's `catchUp` names `module-plugin` for `.claude-plugin/marketplace.json` only. That file lists one plugin, `relay` from `./plugin`: Relay Everything's public plugin list, so it stays. The move has nothing else to do.

## Checks

A trial run with upstream's `app/.oxlintrc.json` on today's `app/` found no design-rule failure; a planted `bg-pink-500` failed. After the copy, run `npm run lint`, `npm run typecheck` (if present) and `npx vitest run src/style.test.ts` in `app/`, and `node scripts/check-app-checks.mjs` from the root.
