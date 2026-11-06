---
title: Connections
description: Send your Relay Everything data to your own database, let your own AI read it, and save your Claude Code chats.
---

Connections move your notes, health and location from Relay Everything to the place you choose, where your own AI can read them. Three work today: webhooks to your own database, the AI connector, and the Relay Everything plugin that saves your Claude Code chats. The others are coming, so this page gives no steps for them.

Relay Everything does not store your data for your AI, and it gives you no plugin format or access roles. You keep your own database, tables and tools. Relay Everything collects the data and sends it to them.

## Your own database

A webhook sends each new note, and the health and location you tick, to an address you own, in one signed format. [Your own database](your-database/) shows how to add one, each message, and an example receiver.

## AI assistants (MCP)

Your AI assistant reads your notes, health, places and chats through MCP, the Model Context Protocol: [Connect your AI](connect-your-ai/).

## Claude Code chats

The Relay Everything plugin saves each Claude Code chat to your Relay Everything server: [Save Claude Code chats](claude-code/).

## An example skill and tables

:::note[Coming]
After the connections, an example AI skill and a table setup will come here. Copy them and change them to fit your own data.
:::

Until then, the [server API](../api/reference/) gives your notes to any tool that holds a [device key](../api/keys/).
