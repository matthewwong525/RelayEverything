---
name: saving
description: Turn saving Claude Code and Codex chats to Relay Everything on or off for this project, or say which it is. Use for /relay:saving, "stop saving this project to Relay Everything", "don't send this chat to Relay Everything", or "is this project saved to Relay Everything".
argument-hint: "[on|off]"
allowed-tools: Bash(node:*)
---

# Saving to Relay Everything

`${CLAUDE_PLUGIN_ROOT}` is the plugin's folder. In Codex it is empty: use the folder two levels above this file, and put the person's words in place of `$ARGUMENTS`.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it. In Codex's sandbox, the command can not reach the network or write this computer's Relay Everything folder.

Run this command in the project, with the person's choice: `on`, `off`, or nothing to see which it is.

```bash
node "${CLAUDE_PLUGIN_ROOT}/bin/saving.mjs" $ARGUMENTS
```

Show the person the lines it prints, word for word, and nothing more.
