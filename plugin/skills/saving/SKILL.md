---
name: saving
description: Turn saving Claude Code chats to Relay Everything on or off for this project, or say which it is. Use for /relay:saving, "stop saving this project to Relay Everything", "don't send this chat to Relay Everything", or "is this project saved to Relay Everything".
argument-hint: "[on|off]"
allowed-tools: Bash(node:*)
---

# Saving to Relay Everything

Run this command with the person's choice, `on`, `off`, or nothing to see which it is:

```bash
node "${CLAUDE_PLUGIN_ROOT}/bin/saving.mjs" --data "${CLAUDE_PLUGIN_DATA}" $ARGUMENTS
```

Show the person the lines it prints, word for word, and nothing more.
