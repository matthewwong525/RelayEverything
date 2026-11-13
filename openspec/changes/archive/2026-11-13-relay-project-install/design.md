# Design

## Context

- `plugin/` holds the hooks (`hooks/hooks.json` → `bin/hook.mjs`), six skills that call `node "${CLAUDE_PLUGIN_ROOT}/bin/…"`, the scripts in `bin/` and `lib/`, the build prompts in `build/`, and the WongStack memory copy in `memory/`. Claude Code and Codex keep it in their plugin cache and replace it on each update.
- Per-computer state is already outside the plugin, in `~/.config/relay-everything/` (`lib/config.mjs`): `computer.json` (key, server, name, memory choice), `state/`, `knowledge/`, `build.json`, `build/`.
- WongStack modules already install at project level for both apps ([memory's setup](../../../.agents/skills/memory/references/setup.md)): hooks merged into `.claude/settings.json` and `.codex/hooks.json`, each group added only when missing; the skill in `.claude/skills/` linked into `.agents/skills/` for Codex. Codex runs project hooks once the person trusts the project.
- Claude Code runs project hooks with `$CLAUDE_PROJECT_DIR`; WongStack's Codex hooks find the project with `$(git rev-parse --show-toplevel)`.

## Goals / Non-Goals

**Goals:** the install and the update are scripts, not AI judgment, except for clashes; one source in this repository, `plugin/`, for both the copy and the last plugin; every per-computer file stays in `~/.config/relay-everything/`.

**Non-Goals:** a home-folder install; Windows paths beyond what the plugin handles today; publishing to npm.

## Decisions

### 1. The copy's layout

```text
<project>/
  .agents/relay/                 copy of plugin/ minus .claude-plugin/, test/
    RELEASE                      "0.8.0 <commit or tag>" the copy came from: the commit
                                 from a git checkout, else the tag relay-v0.8.0
    skills/<name>/SKILL.md       renamed relay-<name>
  .claude/skills/relay-<name>    → ../../.agents/relay/skills/<name>
  .agents/skills/relay-<name>    → ../relay/skills/<name>
  .claude/settings.json          + Relay Everything's hook groups
  .codex/hooks.json              + the same, for Codex
```

Links, not copies, so one edit serves both apps. A name already taken by another skill is skipped and reported, as WongStack's setup does.

*Alternative:* the copy in `.claude/skills/relay/` like WongStack memory. Rejected: Relay Everything has six skills plus shared scripts, so one folder that is not itself a skill is clearer.

### 2. Paths

Skills call `node "$(git rev-parse --show-toplevel)/.agents/relay/bin/<script>.mjs"`. Hooks call `node "$CLAUDE_PROJECT_DIR/.agents/relay/bin/hook.mjs" <event>` in Claude Code and the `git rev-parse` form in Codex. Every script finds its own folder from `import.meta.url`, so nothing reads `CLAUDE_PLUGIN_ROOT` any more; `appOf` in `headless.mjs` tells Codex from Claude Code by the transcript and `CODEX_THREAD_ID` only.

### 3. Install

`plugin/install.mjs --into <project>`, a plain Node script with no dependencies:

1. Refuses when `<project>` is not a git project. When `.agents/relay/RELEASE` exists, changes nothing and prints `already installed: <version>; type /relay-update`.
2. Copies its own release's files into `.agents/relay/`, writes `RELEASE`, makes the links, and merges the hook groups into both settings files, adding only missing groups and keeping every other key.
3. Prints `installed=<version>` and whether `computer.json` exists.

The prompt on the site, `Install Relay Everything in this project: follow https://relayeverything.com/install/`, sends the AI to a page that says: download the newest `relay-v*` release's tarball from GitHub into a new temporary folder, run its `install.mjs --into "$(git rev-parse --show-toplevel)"`, then run `/relay-connect` when the computer is not connected, and tell Codex users to trust the project's hooks. The page is the one place the steps live.

*Alternative:* `curl … | node`. Rejected: the AI's steps on a page are visible to the person and can stop at each one.

### 4. Releases

The plugin release step in `wiki/stack/relay-chats.md` adds a git tag `relay-v<version>` on `main` after the version change merges. The tarball comes from `https://codeload.github.com/matthewwong525/RelayEverything/tar.gz/refs/tags/relay-v<version>`; only its `plugin/` folder is used. The newest is the highest `relay-v*` tag from the GitHub tags API.

### 5. Update: a three-way merge

`plugin/update.mjs` in the copy (`.agents/relay/update.mjs`), run by `/relay-update`:

1. `check`: reads `RELEASE`, finds the newest tag, prints `current= newest=` and the list of changed files, or `up_to_date`.
2. `plan`: downloads the base release (the one in `RELEASE`) and the newest into a temporary folder. For each file: changed only upstream → take the new text; changed only in the copy → keep it; both changed → `git merge-file -p` into a result. A clean merge is ready; a merge with conflict markers is a clash. Files added upstream are added; files deleted upstream that the person did not change are deleted. It writes nothing to the copy and prints the per-file plan.
3. `apply`: writes the plan's results after the person agrees, with clashes already chosen by the person through the AI, then rewrites `RELEASE`, re-runs the link and hook-merge steps of the install for a new or removed skill or hook, and prints `updated=<version>`.

The skill shows the plan in plain words, walks each clash with the person, and never runs `apply` without a yes. The person commits the result as they like.

*Alternative:* `git merge` from a remote. Rejected: the copy is a folder inside the person's own repository, not its own history.

### 6. The last plugin, 0.7.0

- `hook.mjs` in the plugin returns nothing at all when the chat's project has `.agents/relay/RELEASE`: the copy's own hooks do the work.
- In a project with no copy, the first `SessionStart` on each computer shows once: *Relay Everything moved into your projects. Say "move Relay Everything here" to install it in this project.*
- A new skill, `/relay:move`, runs the plugin's own `install.mjs --into <project>`, says that `computer.json` is kept, and on the person's yes runs `claude plugin uninstall relay@relay` and `codex plugin remove relay@relay`.
- After one release, `.claude-plugin/marketplace.json` and the Codex manifest are removed in a later change.

### 7. Per computer, not per project

The key, `state/`, `knowledge/`, `build.json` and `build/` stay in `~/.config/relay-everything/`. The daily build starts from whichever project's copy has the day's first chat; the existing lock and claim keep it to one run. Two projects on different releases each run their own scripts against the same state; `state/` and `computer.json` keep their current shapes so an older copy reads a newer file.

## Risks / Trade-offs

- [A person's edit breaks saving] → it is their copy; `/relay-update` can still merge, and the site's install page says how to start fresh.
- [A clash in a script the person can't read] → the skill offers *keep the release's version* for each clash.
- [Chats in projects without the copy are no longer saved] → said on the install page and in the move message.
- [Two copies on different releases disagree about a state file's shape] → state files only gain fields; the tests check that the previous release reads the new shape.
- [Codex runs no project hook until the project is trusted] → the install's last line says to trust it.

## Migration Plan

1. Ship 0.8.0 sources with `install.mjs`, `update.mjs`, renamed skills, and the 0.7.0 plugin bits (`/relay:move`, step-aside). The plugin's manifest says 0.7.0; `RELEASE` in a copy says 0.8.0 from the same tag, `relay-v0.8.0`.
2. Publish the site with the install page.
3. Matthew moves this repository's own use first, on staging, then on live.
4. A later change removes the plugin manifests.

Rollback: delete `.agents/relay/`, the `relay-*` links and the hook groups from a project; the plugin still works where it is installed.
