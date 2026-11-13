---
title: Install in a project
description: Install Relay Everything in a Claude Code or Codex project by pasting one prompt. The copy is yours to change, and it saves the project's chats.
---

Relay Everything installs as your own copy inside a project. Each file of the copy is yours: change any skill or script, and keep it in your own GitHub with the rest of the project. The copy saves the project's Claude Code and Codex chats to your Relay Everything, and lets your AI read your notes, health, places and calendar: [Save AI chat transcripts](../connections/claude-code/).

## Paste the prompt

Open Claude Code or Codex in the project you want saved, and paste:

```text
Install Relay Everything in this project: follow https://relayeverything.com/install/
```

Your AI reads this page, does the steps below, and shows each one:

```text
copied into .agents/relay/
set up for Claude Code and Codex
Open this link to connect: …
```

## Each project saves on its own

A project with the copy saves its chats. A project with no copy and no plugin saves nothing. Install it in each project you want saved. One sign-in on a computer serves every project with the copy, so a second project needs no second sign-in.

To keep one project's chats out later, type `/relay-saving off` there.

## The AI's steps

These are the steps for your AI. Run each command from the project. In Codex, run them outside the sandbox: they reach GitHub and this computer's Relay Everything folder.

1. Get the newest release into a new, empty folder. A release is a `relay-v<version>` tag of the public Relay Everything repository:

   ```bash
   tag=$(git ls-remote --tags --refs https://github.com/matthewwong525/RelayEverything 'relay-v*' | sed 's#.*refs/tags/##' | sort -V | tail -n 1)
   dir=$(mktemp -d)
   curl -fsSL "https://codeload.github.com/matthewwong525/RelayEverything/tar.gz/refs/tags/$tag" | tar -xz -C "$dir" --strip-components=1
   ```

2. Install it into the project:

   ```bash
   node "$dir/plugin/install.mjs" --into "$(git rev-parse --show-toplevel)"
   ```

   It copies Relay Everything into `.agents/relay/`, links its skills for Claude Code and Codex, and adds its hooks to `.claude/settings.json` and `.codex/hooks.json`. It keeps every other hook, skill and setting. When the project has the copy already, it changes nothing and says *type /relay-update*. Show the person the lines it prints. Then delete the folder: `rm -rf "$dir"`.
3. When it prints `connected=no`, connect this computer: do the steps of the new `relay-connect` skill in `.claude/skills/relay-connect/SKILL.md`, or `.agents/skills/relay-connect/SKILL.md` in Codex. Claude Code lists the new skills in the next chat.
4. In Codex, tell the person to trust the project's hooks when Codex asks, or with `/hooks`. Codex runs no hook that the person did not trust, and says nothing, so with no trust it saves no chat.

## What goes in the project

```text
your-project/
  .agents/relay/      Relay Everything, yours to change
    skills/  bin/  lib/  build/  memory/
    RELEASE           the release it came from
  .claude/skills/relay-*    links to it
  .agents/skills/relay-*    links to it, for Codex
```

Your key never goes in the project. It stays in this computer's own Relay Everything folder, `~/.config/relay-everything/`, with the chats waiting to send and your copy of the knowledge web. So you can push the project with the copy to your own GitHub.

The skills are `/relay-connect`, `/relay-ask`, `/relay-save`, `/relay-saving`, `/relay-memory`, `/relay-build` and `/relay-update`. In Codex, type `$relay-connect` and so on.

## Update

Type `/relay-update` (`$relay-update` in Codex). It gets the newest release, shows what it changes, and merges it with your own edits. Where you and the release changed the same lines, your AI shows both and asks which to keep: yours, the release's, or both. Nothing changes until you say yes.

```text
/relay-update
  0.8.0 → 0.9.0: 3 skills, 2 scripts
  ask skill: merged with your edits
  hook.mjs: you and the update both
    changed line 40 → keep which?
```

## Start fresh

If an edit stops the copy from working, delete `.agents/relay/`, the `relay-*` links in `.claude/skills/` and `.agents/skills/`, and Relay Everything's hooks in `.claude/settings.json` and `.codex/hooks.json`. Then paste the prompt again. Your computer stays connected.

## From the plugin

If you have the Relay Everything plugin, it says once that Relay Everything moved. Say *move Relay Everything here* in a project: it installs the copy there and keeps your sign-in. When you say so, it removes the plugin from Claude Code and Codex. While both are in a project, only the copy saves, so no chat is sent twice. Until you remove the plugin, it keeps saving the projects that have no copy.
