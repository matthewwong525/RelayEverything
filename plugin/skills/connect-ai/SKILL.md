---
name: connect-ai
description: Add your Relay Everything server's AI connector to Claude Code, so it can read your Relay Everything notes, health, places and chats. Use for /relay:connect-ai, "connect Claude Code to Relay Everything", or "let Claude Code read my Relay Everything notes".
argument-hint: "https://<your-relay-server>/mcp"
allowed-tools: Bash(node:*)
---

# Connect Claude Code to Relay Everything

The person gives the connector address from the **AI apps** card on their Relay Everything page. If they gave none, ask for it, and say where it is.

```bash
node "${CLAUDE_PLUGIN_ROOT}/bin/connect-ai.mjs" "<address>"
```

Show the person the lines it prints, word for word. Never type their sign-in for them: they type `/mcp`, pick `relay` and sign in themselves.
