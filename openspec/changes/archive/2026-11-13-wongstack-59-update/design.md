# Design

## Context

The install record (`.claude/.wong-stack.json`) says 55.2.1 at commit `a282a4a9`. The source checkout at `/root/.cache/wong-stack/WongStack` was at 59.0.0, commit `facaf5f9`, fast-forwarded on 2026-11-12; 60.0.0 (`c7450cee`) followed the same day and adds only the unpacked commands (task 5.2); 61.0.0 (`9d63c758`, 2026-11-13) runs each module's hooks from the project's settings, with no plugins (task 5.3). The preflight reports `status: update`, 827 units in the union, 223 changed, `catchUp.needed: false`, `updatingComplete: true`.

Rerun it at build time, and write its JSON to a file only this chat uses (`.scratch/wong-preflight.json`), because another chat on this computer wrote `/tmp/wong-preflight.json` during planning:

```bash
node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/preflight.mjs \
  --target <this checkout> --source /root/.cache/wong-stack/WongStack \
  --record .claude/.wong-stack.json > .scratch/wong-preflight.json
```

Its `changes` list gives each unit's `sourcePath`, `targetPath`, `operation` and `localState`, and is the copy list.

| operation / local state | count | action |
|---|---|---|
| modified / installed-equivalent | 97 | copy by `install-path.mjs` |
| added / missing | 46 | copy by `install-path.mjs` |
| modified / latest-equivalent | 5 | nothing |
| removed / installed-equivalent | 46 | `git rm` |
| removed / locally-adapted | 6 | `git rm` (no local line; see below) |
| modified / locally-adapted | 23 | 16 copy whole, 1 copy (upstream has the fix), 6 merge |

Copy each unit with `node <source>/.claude/skills/wong-sync/scripts/install-path.mjs --source <source> <sourcePath> > <targetPath>`. Copy the `CLAUDE.md` unit, the marked `WONG-STACK` block only, into `AGENTS.md` between its markers, keeping every line outside them.

### Where the moved parts land

- **Browser** (57.0.0): hand-over and shop move into `.claude/skills/browser/skills/{hand-over,shop}/`; the browser gets `.claude-plugin/` and `.codex-plugin/` manifests. The old `.claude/skills/{hand-over,shop}/` go. The browser has no hooks.
- **Daily** (57.0.0): schedule moves into `.claude/skills/daily/skills/schedule/`. The old `.claude/skills/schedule/` goes. `module.json` files go; versions live in the two `plugin.json` files.
- **Loop** (56.0.0): `.claude/skills/continue/` goes; `.claude/skills/apply/references/pick-up.md` and its script arrive.
- **Memory** (58.0.0, 59.0.0): the QMD files under `scripts/lib/documents/` and the nested `skills/dream-memory/` go; `scripts/daily-tidy.mjs`, `scripts/lib/usage.mjs`, `references/tidy.md` and `references/placing-facts.md` arrive. No D1 migration is added.
- **Inbox** (58.0.0): `.claude/inbox/move-in.mjs` and `.claude/inbox/lib/legacy.mjs` go.
- **Wiki**: `wiki/stack/legacy-cloud-schedules.md` goes.

### Merge list (locally adapted)

Six files keep local lines. Take upstream's version, then put back the local line:

- `.claude/skills/plan/SKILL.md`: the phone app link, *a phone app screen by its screen test* (link to `wiki/development/phone-pictures.md`).
- `.claude/skills/plan/references/drawings.md`: the tip *Open its page in a browser before you build …*.
- `wiki/development/daily.md`: the line linking [ship every chat from one chat](../../../wiki/development/ship-every-chat.md).
- `wiki/review-pages.md`: the paragraph *A phone app screen gets its pictures from a screen test …*.
- `wiki/stack/README.md`: the four Relay Everything entries (*Move Cloudflare data*, *AI connector*, *memory and knowledge web*, *AI chat transcripts*).
- `wiki/ux-principles.md`: the brand page sentence.

If upstream moved the text a local line sits in (57.1.2 moved some plan text into `.claude/skills/plan/references/review-page.md` and `prototypes.md`), put the line beside the text it belongs to and name the move in the Decision log.

Take upstream whole: the 16 changed files whose only difference from the 55.2.1 copy is the install's path rewriting, the 6 removed ones (`.claude/skills/continue/*`, `.claude/skills/schedule/{SKILL.md,references/migration.md,references/registration.md}`, `wiki/stack/legacy-cloud-schedules.md`), and `.claude/skills/daily/scripts/worker.mjs`, whose local lines are the *retired* fix that 57.1.1 shipped upstream.

### Files outside the payload

- `wiki/development/README.md`: point the hand-over and shop links at `.agents/skills/browser/skills/{hand-over,shop}/references/`.
- `app/package.json`: the `npm test` line runs `.agents/skills/daily/skills/schedule/scripts/tidy.test.mjs`, not the old schedule path.
- `.env.example`: remove the *Legacy cloud scheduling* block (`WONG_ROUTINES_KEY`, `WONG_ROUTINE_MODEL_KEY`); the page it names goes, and `/root/relay-ring/.env` holds no value for either.
- `.claude/settings.json` and `.codex/hooks.json`: take 61.0.0's whole. Each local hook is already in upstream's, so each runs once; `enabledPlugins` goes with the five module plugin manifests.
- `.claude-plugin/marketplace.json`: unchanged, Relay Everything only. 61.0.0's catch-up names it, but it lists no module.
- Codex: after the merge, run `codex-plugin.mjs` once. It removes `memory@wongstack` and `daily@wongstack` and adds nothing.

### The plugin's memory copy

`plugin/memory/` is a copy of `.claude/skills/memory/`, and `plugin/test/memory-copy.test.mjs` fails while it differs ([relay-chats](../../../wiki/stack/relay-chats.md)). After the memory copy:

- Run `node scripts/copy-plugin-memory.mjs`. Drop `skills/dream-memory/`, `scripts/lib/documents/runtime/`, `.claude-plugin/` and `.codex-plugin/` from its `LEFT_OUT`, because all four are gone upstream.
- Raise `plugin/.claude-plugin/plugin.json` `version` to 0.6.1.
- Add one sentence to the memory part of `plugin/README.md` and `site/src/content/docs/connections/claude-code.md`: memory counts each look-up in a file on this computer, for 30 days, with the words only of a question that found nothing; it never leaves the computer.
- `plugin/memory-profile.mjs` needs no change: 59.0.0 adds `prepare` only for the daily tidy, which the plugin leaves out.

## Goals / Non-Goals

**Goals:** run WongStack 61.0.0 with every local line kept; keep the plugin's memory copy equal to the module; record the new version.

**Non-Goals:** the daily tidy in the plugin; sending the local lines upstream; any Relay Everything route, table or phone app change.

## Decisions

- Copy by the preflight list, not by a folder copy, so no source-only file and no `app/wrangler*.jsonc` arrives.
- The plugin goes to 0.6.1 in this change, because the copy test fails otherwise, and an unchanged version means installed plugins never update.

## Risks / Trade-offs

- A moved plan reference may lose a local line → `merge-check.mjs` names each missing line before the record moves.
- Removing `.claude/skills/schedule/` while the helper service runs relay-ring's schedule code → no risk: the helper runs ClaymooApp's newer install (memory #570), and the app schedule records stay.

## Migration Plan

After the merge to `main`:

1. Run `node .claude/skills/wong-sync/scripts/codex-plugin.mjs --root <this checkout>` once.
1. Run `node scripts/publish-relay-site.mjs`, then `node scripts/publish-relay-server.mjs`, and report both `result=` lines.
2. In a new chat, check that the start line shows the memory digest and that `/schedule list` lists the two schedules.

Rollback: revert the merge commit; the install record goes back with it.
