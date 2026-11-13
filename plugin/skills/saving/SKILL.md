---
name: relay-saving
description: Turn saving Claude Code and Codex chats to Relay Everything on or off for this project, or say which it is. Use for /relay-saving, "stop saving this project to Relay Everything", "don't send this chat to Relay Everything", or "is this project saved to Relay Everything".
argument-hint: "[on|off]"
allowed-tools: Bash(node:*)
---

# Saving to Relay Everything

Each command runs Relay Everything's copy in this project, `.agents/relay/`. When that folder is missing, this is the Relay Everything plugin: in each command, put the folder two levels above this file in place of `$(git rev-parse --show-toplevel)/.agents/relay`. Never install the copy unless the person asks: `/relay:move` moves it into this project. In Codex, put the person's words in place of `$ARGUMENTS`.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it. In Codex's sandbox, the command can not reach the network or write this computer's Relay Everything folder.

Run this command in the project, with the person's choice: `on`, `off`, or nothing to see which it is.

```bash
node "$(git rev-parse --show-toplevel)/.agents/relay/bin/saving.mjs" $ARGUMENTS
```

Show the person the lines it prints, word for word, and nothing more.
