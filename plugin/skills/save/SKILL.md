---
name: save
description: Save this chat to Relay Everything with a short title and a summary of what was decided and why. Use for /relay:save, or when the person asks to save the chat, a plan or a decision to Relay Everything.
allowed-tools: Bash(node:*)
---

# Save this chat to Relay Everything

`${CLAUDE_PLUGIN_ROOT}` is the plugin's folder. In Codex it is empty: use the folder two levels above this file.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it. In Codex's sandbox, the command can not reach the network or write this computer's Relay Everything folder.

Write a title of a few words that names what the chat decided, and a summary in plain words of what was decided and why. Then run this command, with the title on the first line and the summary after it:

```bash
node "${CLAUDE_PLUGIN_ROOT}/bin/save.mjs" --session "${CLAUDE_SESSION_ID}" <<'RELAY_SAVE'
<title>
<summary>
RELAY_SAVE
```

It sends the chat so far, then your title and summary beside it. Tell the person the line it prints.
