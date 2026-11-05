---
title: Run your own Relay server
description: Make your own Relay server in your own Cloudflare account, with one request to your AI. Relay's apps only add data to it.
---

Your Relay server keeps what your phone, the Pebble app and Claude Code send. You make it in your own Cloudflare account, so it and its data are yours. Relay's apps only add data to it: they can't read it back. You read it on your Relay page, and your own AI reads it through your AI connector.

## Make it

Paste this request into Claude Code or another coding AI:

```text
Install Relay from https://github.com/matthewwong525/RelayEverything.
Read and follow self-host/SETUP.md there.
```

The AI follows Relay's setup guide. It asks you to make a Cloudflare key and save it in a file on your computer, never in the chat. Then it makes your server and gives you its address. It takes about 10 minutes.

:::note
Cloudflare's free plan is enough. Cloudflare asks you to turn on two parts once, in its dashboard: R2, for recordings, and Zero Trust, for your login. Both are free, but Cloudflare can ask for a payment card before it turns on R2.
:::

## What you get

| Your server has | Your server does not have |
|---|---|
| Relay's server: notes, recordings, health, places and AI chats | The tools that build Relay |
| Your Relay page, with your email as its only login | A login for anyone else |
| A key for each phone, Pebble app and Claude Code computer | A way for a key to read your data |
| Your AI connector, so your own AI reads your data | A way in for Relay's makers |
| [Webhooks](../../connections/your-database/) to your own database | A cost, on the free plan |

## Your devices

Make a key for each device on the computer where you made the server:

```sh
node scripts/relay-device-key.mjs create --name "iPhone"
```

[Connect a phone](../connect-a-phone/) tells the rest. A key only adds data: [Keys](../../api/keys/#what-a-device-key-reaches).

## Update it

Ask your AI *update my Relay*. It gets the newest Relay, applies its database changes, then puts it live. Your data stays. If a database change fails, your server stays as it was.

## Remove it

Ask your AI *remove my Relay*. It shows what it will delete and asks first: the server, its notes, recordings, health and places, and its keys. This can't be undone.
