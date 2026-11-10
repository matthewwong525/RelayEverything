---
name: build
description: See, stop, start or run the daily build of the person's Relay Everything knowledge web on this computer. Use for /relay:build, "when did my knowledge web last build", "stop building my Relay Everything web", "turn the daily build back on", or "build my knowledge web now".
argument-hint: "[off|on|now]"
allowed-tools: Bash(node:*)
---

# The daily build

Once a day, the first chat on this computer starts a build in the background: the person's own AI reads their older chats and notes into facts, gives notes their topics, and writes and links their topic pages. It uses the person's own plan, at most 30 minutes a day.

`${CLAUDE_PLUGIN_ROOT}` is the plugin's folder. In Codex it is empty: use the folder two levels above this file, and put the person's words in place of `$ARGUMENTS`.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it. In Codex's sandbox, the command can not reach the network or write this computer's Relay Everything folder.

Run this command with the person's choice: nothing to see the last build, `off` to stop the daily build on this computer, `on` to start it again, or `now` to start one at once.

```bash
node "${CLAUDE_PLUGIN_ROOT}/bin/build.mjs" status
node "${CLAUDE_PLUGIN_ROOT}/bin/build.mjs" off
node "${CLAUDE_PLUGIN_ROOT}/bin/build.mjs" on
node "${CLAUDE_PLUGIN_ROOT}/bin/build.mjs" now
```

Show the person the lines it prints, word for word, and nothing more.
