# Design

## Context

The install record (`.claude/.wong-stack.json`) says 61.3.0 at commit `102e1abb`. The source checkout at `/root/.cache/wong-stack/WongStack` is at 61.5.0, commit `a43bb2af`, fast-forwarded on 2026-11-13. Its two commits since `102e1abb` are 61.4.0 (PR #598, another chat's browser turn never stops yours) and 61.5.0 (PR #600, a helper per project).

The preflight reports `status: update`, 772 units, 22 changed, all `modified` / `installed-equivalent`, `updatingComplete: true`. Rerun it at build time into a file only this chat uses:

```bash
mkdir -p .scratch
node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/preflight.mjs \
  --target <this checkout> --source /root/.cache/wong-stack/WongStack \
  --record .claude/.wong-stack.json > .scratch/wong-preflight.json
```

Copy each unit with `node <source>/.claude/skills/wong-sync/scripts/install-path.mjs --source <source> <sourcePath> > <targetPath>`.

## The changed parts

- **Browser** (`.claude/skills/browser/`, 61.4.0): `SKILL.md`, `VERSION`; references `browser-window.md`, `browsing.md`; scripts `browse.mjs`, `browser-server.mjs`, `connect-browser.mjs`. **Hand-over**: `skills/hand-over/references/live-view.md`, `skills/hand-over/scripts/hand-over.mjs`.
- **Helper** (`.claude/skills/reply-link/scripts/`, 61.5.0): `helper.mjs`, `lib/computer.mjs`, `lib/helper-log.mjs`, `reply-link.mjs`. **Inbox runner**: `.claude/inbox/runs.mjs`, `.claude/inbox/schedules.mjs`.
- **Admin app Inbox**: `app/src/apps/inbox/cadence.ts` (new `not_signed_in` reason) and its tests `cadence.test.ts`, `Schedules.test.tsx`, `app/worker/apps/inbox/schedules.test.ts`.
- **Wiki**: `wiki/stack/connect-your-tools.md`, `host-schedules.md`, `live-line.md`.

## Catch-up

The preflight's `catchUp` names `module-plugin` for `.claude-plugin/marketplace.json` only. That file lists one plugin, `relay` from `./plugin`: Relay Everything's public plugin list, so it stays. `.claude/settings.json` has no `enabledPlugins` and no `@skills-dir` key, there is no `.claude/settings.local.json`, and its one helper hook (`helper.mjs start`) is the shipped one. The move has nothing to do.

## The helper install

After publish, the main folder `/root/relay-ring` must hold the 61.5.0 code: its auto-sync timer fast-forwards it to `origin/main`; if it has not moved, `git -C /root/relay-ring merge --ff-only origin/main` (its untracked `cad/` and `vendor/` stay). `helper.mjs install` refuses a main folder with older code.

Run, from `/root/relay-ring`, at a minute that is not `:X0` or `:X5` (so the shared helper claims no due run in between):

```bash
node .claude/skills/reply-link/scripts/helper.mjs install --dry-run   # read the files and commands
node .claude/skills/reply-link/scripts/helper.mjs install             # expect HELPER=installed
node .claude/skills/reply-link/scripts/helper.mjs status
```

Running as root, it is a system service, `wongstack-helper@<id>.service`, from the shared template unit `wongstack-helper@.service` (already there for `wongos` and `wongstack`). `<id>` is `relay-ring-<8 hex>`. Its folder `~/.wong-stack/helpers/<id>/` holds `run.mjs`, `runs.json` and `log.jsonl`. The install moves relay-ring's started runs and open inbox items off the shared helper; OKs stay in `~/.wong-stack/helper/approved.json`.

**Check, within 10 minutes:** `~/.wong-stack/helpers/<id>/log.jsonl` has a run line for the line-up schedule (*Keep my chats in line*) with outcome `handed`, and the admin app's Inbox › Schedules shows that run, not *Needs your OK*. When no chat needs lining up, the run ends `no_work`: the Inbox leaves it out of the run list and adds one to its quiet-check count (`Schedules.tsx`), which also passes. A `not_signed_in` outcome means this computer's `cloudflared` sign-in to `admin.relayeverything.com` is missing: report it, do not approve anything.

If the install prints `HELPER=failed`, relay-ring stays on the shared helper (the script keeps it there); report the output and stop.

## Codex

`codex-plugin.mjs --check` prints nothing. The last repo task runs it as `/wong-sync` asks; it removes and adds nothing.

## Not touched

No settings, hooks, route, `relay_*` table, memory database, `plugin/` or `site/` file changes. The plugin's memory copy (`scripts/copy-plugin-memory.mjs`) is not affected. `/relay-` commands do not change. No `relay:api-doc` run: no route changes.
