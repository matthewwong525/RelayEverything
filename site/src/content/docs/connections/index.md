---
title: Connections
description: Let your own AI read your Relay data, save your Claude Code chats, and, soon, send your data to your own database.
---

Connections move your notes, health and location from Relay to the place you choose, where your own AI can read them. Two are built: your AI reads Relay through the AI connector, and the Relay plugin saves your Claude Code chats. The others are coming, so they have no steps yet.

Relay does not store your data for your AI, and it gives you no plugin format or access roles. You keep your own database, tables and tools. Relay collects the data and sends it to them.

## Your own database

:::note[Coming]
Webhooks will send each new note, health reading and place to a database you choose. Its set-up steps come here when it is built.
:::

## AI assistants (MCP)

Your AI assistant reads your notes, health, places and chats through MCP, the Model Context Protocol: [Connect your AI](connect-your-ai/).

## Claude Code chats

The Relay plugin saves each Claude Code chat to your Relay server: [Save Claude Code chats](claude-code/).

## An example skill and tables

:::note[Coming]
After the connections, an example AI skill and a table setup will come here. Copy them and change them to fit your own data.
:::

Until then, the [server API](../api/reference/) gives your notes to any tool that holds a [device key](../api/keys/).
