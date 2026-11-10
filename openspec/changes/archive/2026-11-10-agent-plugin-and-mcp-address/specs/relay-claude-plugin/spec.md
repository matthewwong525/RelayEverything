# Spec Delta

## REMOVED Requirements

### Requirement: Chats are sent as they happen
**Reason**: The plugin now serves Claude Code and Codex; `relay-agent-plugin` holds this promise for both.
**Migration**: See `relay-agent-plugin`, *Chats are sent as they happen, from either app*.

### Requirement: A saved chat keeps messages exact and steps short
**Reason**: Moved to `relay-agent-plugin`.
**Migration**: See `relay-agent-plugin`, same name.

### Requirement: Saving can be turned off per project
**Reason**: Moved to `relay-agent-plugin`.
**Migration**: See `relay-agent-plugin`, same name.

### Requirement: The AI can save on request
**Reason**: The save tool becomes a skill, so the plugin starts no connector.
**Migration**: See `relay-agent-plugin`, *The AI saves a summary on request*.

### Requirement: The plugin holds no key or address
**Reason**: The plugin may now name Relay Everything's public address, and the key leaves Claude Code's store for a file both apps read.
**Migration**: See `relay-agent-plugin`, *The plugin holds no key and no private address*.

### Requirement: The plugin can add the AI connector
**Reason**: The plugin reads through skills and needs no connector.
**Migration**: See `relay-agent-plugin`, *The AI reads and adds through skills* and *The plugin points out a doubled connector*.

### Requirement: The plugin sends to the server that made its connect code
**Reason**: There is no connect code; the computer connects to the server `/relay:connect` names.
**Migration**: See `relay-agent-plugin`, *A computer connects by a sign-in link*.
