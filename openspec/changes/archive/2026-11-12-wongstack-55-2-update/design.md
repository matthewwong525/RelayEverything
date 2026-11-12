# Design

## Context

The install record (`.claude/.wong-stack.json`) says 51.10.0 at commit `16a0af7e`. The source checkout at `/root/.cache/wong-stack/WongStack` is at 55.2.1, commit `a282a4a9`, fast-forwarded on 2026-11-12. The preflight (`preflight.mjs --target <this checkout> --source <source> --record .claude/.wong-stack.json`) reports `status: update`, 938 units in the union, 635 changed, `catchUp.needed: false`, `updatingComplete: true`. Rerun it at build time: its JSON lists every unit with `sourcePath`, `targetPath`, `operation` and `localState`, and is the copy list.

| operation / local state | count | action |
|---|---|---|
| modified / installed-equivalent | 186 | copy by `install-path.mjs` |
| added / missing | 268 | copy by `install-path.mjs` |
| removed / installed-equivalent | 153 | `git rm` |
| removed / missing | 1 | nothing |
| modified / locally-adapted | 23 | merge (below) |
| removed / locally-adapted | 3 | move the local lines (below), then `git rm` |
| added / locally-adapted | 1 | keep the target's (below) |

Copy each unit with `node <source>/.claude/skills/wong-sync/scripts/install-path.mjs --source <source> <sourcePath> > <targetPath>`. It rewrites links and imports from `.agents/plugins/<name>/` to the install folder. Copy the `CLAUDE.md` unit, the marked `WONG-STACK` block, the same way into `AGENTS.md` (the target's `CLAUDE.md` links to it), keeping every line outside the markers.

### Where the moved parts land

- **Memory** (`.agents/plugins/memory/` → `.claude/skills/memory/`): the plugin, its hooks (`hooks/claude.json`, `hooks/codex.json`), `store/` (interface, contract), and the nested `skills/dream-memory/`. WongStack's own parts go to `.claude/memory/`: `profile.mjs`, `d1/` (store and migrations 0001-0010), `areas.json`, `knowledge.mjs`, `operations.mjs`, `lookup.mjs`, `topics.mjs`. The old `.claude/skills/memory/{worker,migrations}/` and `.claude/skills/dream-memory/` are removed.
- **Loop** (`.agents/plugins/loop/skills/<verb>/` → `.claude/skills/<verb>/`, own files → `.claude/skills/loop/`); WongStack's parts in `.claude/loop/` (`step-title.mjs`, `ask-check.mjs`, `other-work.mjs`, `helper-stop-check.mjs`, `worktree-secrets.mjs`, `routes/`, `staging/`, `profile.mjs`).
- **Daily** (`.agents/plugins/daily/{daily,schedule}/` → `.claude/skills/{daily,schedule}/`); profile `.claude/daily/profile.mjs`; the schedule store in `.claude/inbox/`.
- **Browser** (`.agents/plugins/browser/{browser,hand-over,shop}/` → `.claude/skills/{browser,hand-over,shop}/`); the eight `wiki/development/` browser guides move into those skills' `references/`; profile `.claude/browser/`; new hidden skill `.claude/skills/reply-link/`.
- **Access** (`.agents/plugins/access/` → `.claude/skills/access/`): screen, server, sign-in, store, scripts, and the nested `skills/services/`; slots `.claude/access/slots.json`; the app gets `app/worker/access-slots.ts`. Removed: `app/src/apps/access/` (now served from the skill's `screen/`), most of `app/worker/employee-access/`, `app/worker/{access,key-rules}.ts`, `app/worker/api/{mcp,services}.ts`, `app/src/lib/seal.ts`, `scripts/{check-service-definitions,lib-services,lib-openapi,lib-scrub,mcp-session}.mjs`.
- **Settings**: `.claude/settings.json` and `.claude/hooks.json` (installed-equivalent) are copied: they no longer name memory or Daily hooks, which the modules bring.

### Merge list (locally adapted)

Run `merge-check.mjs --from 16a0af7ed5b6a02c1f629e2bc0b06e1c58e9fb21` after the merges; each missing hunk is taken or named in the Decision log.

- `.claude/skills/plan/SKILL.md`, `.claude/skills/plan/references/drawings.md`: take upstream; keep the local lines (the *open it in a browser before you build the page* tip, and any other line that differs from the 51.10.0 blob).
- `app/worker/index.ts`: take upstream's imports (`.agents/memory/d1/store.mjs`, `.agents/loop/staging/walk-pictures.mjs`, `access-slots.ts`), the new `keyed(request, …)`, `openStarter`, `/api/services` through `accessFor`, and `accessFor(env).schedule()`. Keep every Relay Everything route and the `relay-only` wiring.
- `app/worker/apps/index.ts`, `app/worker/api/contract.ts`, `app/vite.config.ts`, `app/vitest.config.ts`, `app/knip.jsonc`, `app/package.json`: take upstream's lines; keep the Relay app entries, the Relay test list in `npm test`, and point the service-records check at `../.claude/skills/access/scripts/check-definitions.mjs`.
- Tests: `app/tests/employee-access/connections.ts`, `app/worker/apps/{index,keys,screenless}.test.ts`, `app/worker/employee-access/seed.test.ts`, `app/worker/index.test.ts`, `app/worker/keys.test.ts`: take upstream, keep Relay cases.
- `schema/seed.sql`, `scripts/seal-keys.mjs`, `paseo.json`: take upstream's lines, keep local ones (`paseo.json` keys stay; `worktree.setup` stays a list).
- `wiki/development/daily.md`, `wiki/review-pages.md`, `wiki/stack/cloudflare-access.md`, `wiki/ux-principles.md`: take upstream, keep local sentences (the brand-page link in `ux-principles.md`).

Removed with local lines:

- `wiki/development/browsing.md`: drop the local *When your turn holds the browser* section (53.2.0 replaces it). In `knowledge/people/matthew-wong.md`, point *Another chat's live view* at `.claude/skills/browser/references/browser-window.md` (the turn section) instead.
- `wiki/development/browser-proxy.md`: move *On Matthew's computers, keep the proxy setting on* to `knowledge/people/matthew-wong.md`.
- `app/worker/employee-access/login-management.test.ts`: move the *Relay devices* machine-policy case into the Access module's test that now checks the login policy.

Added with a local file: `.claude-plugin/marketplace.json` stays Relay Everything's public list, unchanged.

### Relay Everything code that names a removed file

- `app/worker/relay-only.ts`, `app/worker/relay-only.test.ts`, `app/tests/relay.ts`, `app/worker/apps/relay/sign-in/{access,connect}.test.ts` import `app/worker/access.ts`: point them at `app/worker/access-slots.ts` (same `getAccessIdentity` and types).
- `wiki/development/README.md` links the eight browser guides: point them at `../../.claude/skills/{browser,hand-over,shop}/references/` per 53.3.0's note, and drop `memory-extraction.md`.
- No skill, hook or script of this repo runs `memory.mjs extract`, `extract-task` or `due`; no tool in `app/worker/keys.ts` uses `mcp`.

## Goals / Non-Goals

**Goals:** the target matches 55.2.1 for every selected unit, with each local line kept or moved; memory, Daily and the loop run from their module folders in Claude Code and Codex on this computer; the memory store takes migration 0010 after deploy.

**Non-Goals:** the Relay Everything plugin's copy of memory (workspace *Relay Everything plugin gets WongStack memory*); WongStack modules in the public plugin list; any `relay_*` table, Relay Everything route, website page or phone app change; WongStack's own tests, journeys, sample plans, VERSION or changelog.

## Decisions

- **Copy by the preflight list, not by folder.** `install-path.mjs` per unit keeps renames and rewritten links exact; a folder copy would bring source-only files. Alternative: rerun setup's `install.mjs`: it writes a fresh install and would overwrite local edits.
- **Keep Relay Everything's root plugin list.** WongStack's module entries would show in the public list that `/plugin marketplace add matthewwong525/RelayEverything` reads. Codex on this computer takes memory and Daily from WongStack's own list instead (`/root/WongStack`, already added as `wongstack`).
- **Remove the `codex-plugin.mjs --check` start hook from `.agents/hooks.json`** as a local edit, because with this repo's list it names `relay@relay`. Record it in the Decision log so the next sync keeps it out.
- **Move the person-specific lines to Matthew's page**, saved through the company knowledge save, not into the module folders, so the next update has nothing to merge there.
- **The plugin's memory waits.** This change only lands the memory module in the repo; the plugin workspace builds the store and the copy on top of it.

## Risks / Trade-offs

- [Claude Code does not load a module's own hooks from its skill folder, and the chat start shows no memory digest] → task 3.3 checks a fresh chat; if no digest shows, add the module hooks to `.claude/settings.json` as a local edit and log it.
- [A Relay file imports a moved app file not found above] → `tsc -b`, `knip` and `npm test` in `app/` fail on it; fix the import to the module's path.
- [Production serves the old `/_memory/` route until the server deploy] → chats keep new facts on the computer and send them after the deploy, per 52.0.0; the Migration Plan deploys before the migrate.
- [The daily tidy publishes a page with a private detail] → each publish runs `scripts/public-check.mjs` in CI; the tidy's pages go through the normal checks.
- [Another computer's Codex lacks Daily] → its next chat names the command, per 55.0.0.

## Migration Plan

1. Copy, delete and merge; run the checks; publish through `/ship`.
2. The merge's deploy (`.github/workflows/deploy.yml`, `cf-build.sh --migrate`) applies the app migration that drops the Inbox chat list and serves `/_memory/v2/`. Then `node scripts/publish-relay-site.mjs` and `node scripts/publish-relay-server.mjs`; report both `result=` lines.
3. Then, as Matthew: `node .claude/skills/memory/scripts/memory.mjs migrate` (memory migration 0010, daily runs). Until then memory works as before and starts no daily tidy. Then start a fresh chat in a checkout of `main`: it prints `# Memory digest`, and `memory.mjs recall "voice notes"` ends with a *files behind these facts* list.
4. `codex plugin add daily@wongstack` on this computer; report its line.
5. The first chat after the update ends the *Wiki tidy* schedule by itself; the first chat of the next day starts the first daily tidy.

Rollback: revert the squash commit and redeploy. Memory migration 0010 rebuilds the runs table with every row and adds a `day` column and a `daily` kind, which the old code ignores. The dropped Inbox chat list does not come back; the old Inbox shows an empty list.
