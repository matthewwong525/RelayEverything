# Spec Delta

## MODIFIED Requirements

### Requirement: One address connects any AI chat app

Relay SHALL offer one remote MCP connector address that a chat app supporting remote MCP with OAuth (the Claude app, Claude Desktop, ChatGPT, Claude Code, Codex) can connect to after a single sign-in, with no key typed or pasted. On Relay Everything's own server that address SHALL be `https://mcp.relayeverything.com`, with nothing after it, and the same address with `/mcp` SHALL work too. Each page and doc that names the address SHALL name it. A browser that opens the address SHALL get a short page that says what it is.

#### Scenario: Connecting the Claude app
- **WHEN** Matthew adds the connector address in the Claude app and approves the Relay sign-in
- **THEN** the app lists Relay's tools and a chat can answer "what did I note yesterday?" from his notes

#### Scenario: Connecting at the new address
- **WHEN** an app adds `https://mcp.relayeverything.com` and the person signs in
- **THEN** the app lists the connector's tools, and the page's *AI apps* shows that address and the app

#### Scenario: The address with /mcp
- **WHEN** an app adds `https://mcp.relayeverything.com/mcp` and the person signs in
- **THEN** the app lists the same tools
