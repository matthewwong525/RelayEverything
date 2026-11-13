---
name: move
description: Move Relay Everything from the plugin into this project, as the project's own copy, and keep this computer's connection. Use for /relay:move, "move Relay Everything here", or when Relay Everything says it moved into your projects.
allowed-tools: Bash(node:*)
---

# Move Relay Everything into this project

Relay Everything is now a copy in each project, not a plugin. The copy saves this project's chats, and the person can change any of its files. A project without the copy saves no chat once the plugin is gone.

`${CLAUDE_PLUGIN_ROOT}` is the plugin's folder. In Codex it is empty: use the folder two levels above this file.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it.

1. Install the copy in this project:

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/install.mjs" --into "$(git rev-parse --show-toplevel)"
   ```

   Tell the person what it did in plain words: the copy is in `.agents/relay/`, its skills are `/relay-ask`, `/relay-save`, `/relay-saving`, `/relay-connect`, `/relay-memory`, `/relay-build` and `/relay-update`, and this computer's connection stays as it was. On `connected=no`, run `/relay-connect`. In Codex, tell them to trust the project when it asks, so its hooks run.
2. Ask: *Remove the plugin from Claude Code and Codex now?* Say that other projects stop saving until they get the copy too. Only on a yes, run each command for the app this computer has:

   ```bash
   claude plugin uninstall relay@relay
   codex plugin remove relay@relay
   ```

   Then tell the person to start a new chat.
