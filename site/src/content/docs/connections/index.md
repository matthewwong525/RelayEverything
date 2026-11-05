---
title: Connections
description: Send your Relay data to your own database, and let your own AI read it. Webhooks work today; the AI connection is coming.
---

Connections move your notes, health and location from Relay to the place you choose, where your own AI can read them. Webhooks to your own database work today. The others are coming, so this page gives no steps for them.

Relay does not store your data for your AI, and it gives you no plugin format or access roles. You keep your own database, tables and tools. Relay collects the data and sends it to them.

## Your own database

A webhook sends each new note, and the health and location you tick, to an address you own, in one signed format. [Your own database](your-database/) shows how to add one, each message, and an example receiver.

## AI assistants (MCP)

:::note[Coming]
Your AI assistant will read your Relay data through MCP, the Model Context Protocol. Its set-up steps come here when it is built.
:::

## An example skill and tables

:::note[Coming]
After the connections, an example AI skill and a table setup will come here. Copy them and change them to fit your own data.
:::

Until then, the [server API](../api/reference/) gives your notes to any tool that holds a [device key](../api/keys/).
