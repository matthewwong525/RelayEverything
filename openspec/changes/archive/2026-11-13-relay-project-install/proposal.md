# Relay Everything as your own copy in each project

**Status:** ready-to-ship
**Branch:** drop-plugins-prompt-install
**Open questions:** none

## Why

The Relay Everything plugin is fixed: a person can use it but can't make it their own, because each update replaces its files. Installed as a copy inside the person's project instead, every file is theirs to change and to keep in their own GitHub, and an update comes only when they ask for it.

## What Changes

- **Install by pasting one prompt.** The website gives a prompt to paste into Claude Code or Codex, in the project you want saved. Your AI copies Relay Everything into the project, sets it up for Claude Code and Codex, and starts the sign-in link. No marketplace, no restart.
  ```text
  You paste:
    Install Relay Everything in this
    project: relayeverything.com/install
  Your AI:
    copied into .agents/relay/
    set up for Claude Code and Codex
    Open this link to connect: …
  ```

- **Every file is yours.** The copy is plain files in your project, so you change any skill or script as you like, and git and your own GitHub keep its history with the rest of your project. Your key never goes in the copy: it stays in your computer's own Relay Everything folder.
  ```text
  your-project/
    .agents/relay/      ← Relay Everything, yours to change
      skills/  bin/  lib/  build/
    .claude/skills/relay-*   → links to it
    .agents/skills/relay-*   → links to it (Codex)
  ~/.config/relay-everything/
    computer.json       ← key, never in git
  ```

- **Update when you want.** Type `/relay-update`. It gets the newest Relay Everything, shows what changed, and merges it with your own edits. Where you and the update changed the same lines, your AI shows both and asks which to keep. Nothing changes until you say yes.
  ```text
  /relay-update
    0.8.0 → 0.9.0: 3 skills, 2 scripts
    ask skill: merged with your edits
    hook.mjs: you and the update both
      changed line 40 → keep which?
  ```

- **Saving is per project.** A project with Relay Everything in it saves its chats; a project without it saves nothing. One sign-in on a computer serves every project that has the copy. *Saving off* in a project and `RELAY_SAVE=0` work as today. Your daily knowledge build still runs once a day on the computer.

- **The commands get new names.** `/relay:connect` becomes `/relay-connect`, and the same for `save`, `saving`, `memory`, `build` and `ask`, because a skill copied into a project has no plugin name in front.

- **The plugin moves you once, then retires.** A last plugin version tells you once, in a chat, that Relay Everything moved. Say *move Relay Everything here*, and it installs the copy in that project and keeps your sign-in. When you say you're done, it removes the plugin from Claude Code and Codex. While both are in a project, only the copy saves, so no chat is sent twice.

- **Non-goals:** one install that saves every folder on the computer; syncing the copy through your Relay Everything space; a merge that never asks you; changes to your data or your key; the phone app's wording (a later change).

## What the build needs

- **Nothing.** A staging trial uses the test person and scratch home that the plugin trials already use.

## Decision log

- **2026-11-13** — Asked whether to drop the plugin for a prompt install → first chose to keep it, then chose a copy the person owns, with an update skill, so they can change it and keep it in their GitHub.
- **2026-11-13** — Asked where the copy lives → chose the project the person is in, not a folder in their home.
- **2026-11-13** — Asked how a person installs → chose pasting a prompt.
- **2026-11-13** — Asked what happens to today's plugin → chose one last version that moves people, then retiring it.
- **2026-11-13** — Asked whether a project install saves only that project → chose only that project.
- **2026-11-13** — Assumed: the copy sits in `.agents/relay/`, with each skill linked into `.claude/skills/relay-<name>` and `.agents/skills/relay-<name>`, because that is how WongStack modules install for both apps.
- **2026-11-13** — Assumed: an update merges by keeping the release the copy came from as the common base (a three-way merge), because then only lines both sides changed need the AI.
- **2026-11-13** — Assumed: updates come from tagged releases of the public repository, `relay-v<version>`, because a tag gives each copy a fixed base to merge from.
- **2026-11-13** — Assumed: the install steps live on a public page that the prompt names, because the steps can then change with no new prompt.
- **2026-11-13** — Assumed: the key, chat state, the knowledge web's copy and the daily build stay in `~/.config/relay-everything/`, one per computer, because they belong to the computer, not to a project, and must never reach git.
- **2026-11-13** — Assumed: the copy's release, 0.8.0, lives in `plugin/VERSION`, because `.claude-plugin/` is not copied and Codex reads the same `plugin.json`, so there is no second manifest to change.
- **2026-11-13** — Assumed: the plugin's hook knows it is the plugin by `CLAUDE_PLUGIN_ROOT` or `PLUGIN_ROOT` in its environment and no `RELEASE` beside it, because the apps give those only to a plugin's hook; on a computer that is not connected, its move message takes the place of the not-connected notice.
- **2026-11-13** — Assumed: a clash's choice holds for the whole file (`git merge-file --ours`, `--theirs` or `--union`), because one choice per file keeps the walk short.
- **2026-11-13** — Assumed: the server's three refusal and link-page lines change to `/relay-connect` in this change, because `/relay:connect` now works nowhere and every person would be sent to a dead command; the phone app's wording waits for a later change, because a phone change starts new app builds.
- **2026-11-13** — Assumed: before the move, the 0.7.0 plugin's skills run the scripts from the folder two levels above their SKILL.md when the project has no copy, and never install the copy unasked (they offer `/relay:move`), because otherwise a plugin user's skills break and a question could install the copy.
- **2026-11-13** — Assumed: `/ship` pushes the tag `relay-v0.8.0` on the merge commit before it publishes the site, because the install page and `/relay-update` find releases only by that tag.
- **2026-11-13** — Assumed: the ask skill may be 6,200 characters, up from 6,000, because the copy's path is longer than `${CLAUDE_PLUGIN_ROOT}`.
- **2026-11-13** — Assumed: archived for `/ship` after the staging trial passed (install, connect, one save with the plugin also loaded, update merge) and the review's six fixes, because every task is done.

## Capabilities

### New Capabilities

- `relay-project-copy`: installing Relay Everything as a copy in a project, by a pasted prompt; the person owning every file; `/relay-update` merging a new release with their edits; the move from the plugin.

### Modified Capabilities

- `relay-agent-plugin`: the install requirement changes from a plugin to a project copy; saving becomes per project with the copy; the no-key rule covers the copy.

## Impact

- `plugin/` stays the source in this repository, renamed in place only where needed: a new `install.mjs` and `update.mjs`, hooks files for Claude Code and Codex at project level, skills renamed `relay-<name>` and their paths moved off `${CLAUDE_PLUGIN_ROOT}`, `lib/headless.mjs` paths.
- Plugin 0.7.0, the last: a move skill and a hook that steps aside where a project has the copy. `.claude-plugin/marketplace.json` and the Codex manifest stay one release, then go.
- A release step tags `relay-v<version>`.
- `site/`: a new *Install* page and changed connection pages. `AGENTS.md`: the `/relay:` command names become `/relay-`. Docs: `plugin/README.md`, `wiki/stack/relay-chats.md`, `wiki/stack/relay-knowledge-web.md`.
- Three server messages say `/relay-connect` (`sign-in/computer.ts`, `caller.ts`, `device.ts`). No server route, no migration, no new key.
