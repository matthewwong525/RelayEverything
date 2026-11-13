# Design

## Context

The install record (`.claude/.wong-stack.json`) says 61.0.0 at commit `9d63c758`. The source checkout at `/root/.cache/wong-stack/WongStack` is at 61.3.0, commit `102e1abb`, fast-forwarded on 2026-11-13. Its four commits since `9d63c758` are 61.1.0 (1Password icon, passkeys, closing its boxes), 61.2.0 (emoji chat names), 61.3.0 (bell on waiting tabs, one *Hand back*), and a WongStack-only wiki tidy.

The preflight reports `status: update`, 772 units in the union, 23 changed, `updatingComplete: true`. Rerun it at build time into a file only this chat uses:

```bash
mkdir -p .scratch
node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/preflight.mjs \
  --target <this checkout> --source /root/.cache/wong-stack/WongStack \
  --record .claude/.wong-stack.json > .scratch/wong-preflight.json
```

| operation / local state | count | action |
|---|---|---|
| modified / installed-equivalent | 20 | copy by `install-path.mjs` |
| added / missing | 3 | copy by `install-path.mjs` |

Copy each unit with `node <source>/.claude/skills/wong-sync/scripts/install-path.mjs --source <source> <sourcePath> > <targetPath>`, making the target folder first for the added `addon/` files.

## The changed parts

- **Browser** (`.claude/skills/browser/`, 3.0.0 → 3.2.0): `SKILL.md`, `VERSION`; references `browser-window.md`, `browsing.md`, `login-codes.md`, `password-manager.md`; scripts `addons.mjs`, `browse.mjs`, `browser-server.mjs`; new `addon/background.js`, `addon/bell.svg`, `addon/manifest.json` (the bell and *Hand back* add-on, which `addons.mjs` installs at the browser's next start).
- **Hand-over** (`.claude/skills/browser/skills/hand-over/`): `references/live-view.md`; scripts `hand-over.mjs`, `view-page.html`, `view-page.mjs`, `view.mjs`. Its top-level copy `.claude/skills/hand-over/SKILL.md` changes too.
- **Daily** (`.claude/skills/daily/`, 4.0.0 → 4.1.0): `VERSION`, `scripts/chat-list.mjs`, `scripts/chats.mjs` (read emoji chat names and old ones).
- **Loop**: `.claude/loop/step-title.mjs` writes the emoji names.
- **Wiki**: `wiki/development/the-change-loop.md`, one paragraph about chat names.

## Catch-up

The preflight's `catchUp` names `module-plugin` for `.claude-plugin/marketplace.json` only. That file lists one plugin, `relay` from `./plugin`: it is Relay Everything's public plugin list, not a WongStack module list, so it stays. `.claude/settings.json` has no `enabledPlugins` and no `@skills-dir` key, there is no `.claude/settings.local.json`, and each module hook appears once. No module folder has a `.claude-plugin/`. The move has nothing to do.

## Codex

`codex-plugin.mjs --check` prints nothing: Codex on this computer has no WongStack module plugin (they went after PR #126). The last task runs it as `/wong-sync` asks; it removes and adds nothing.

## Not touched

No settings, hooks, app, route, `relay_*` table, memory database, `plugin/` or `site/` file changes. The plugin's memory copy (`scripts/copy-plugin-memory.mjs`) is not affected, because memory did not change. No website or server publish.
