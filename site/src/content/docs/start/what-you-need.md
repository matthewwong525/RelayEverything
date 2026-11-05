---
title: What you need
description: The server, phone and keys you need before you use Relay, and an optional ring.
---

To take notes, you need only a phone with the Relay app: the notes stay on it. To send them on, you also need a Relay server and a key for each device. A ring to talk into is optional.

| What | Why |
|---|---|
| **A Relay server** (to send) | It keeps the notes, health and places you send. You [run your own](../run-your-own/), in your own Cloudflare account, behind your own login. You make the keys. |
| **An iPhone or an Android phone** | The Relay app shows your notes, and sends a typed note, your health and where you go. |
| **A key for each device** (to send) | Each phone and the Pebble app has its own key. A key only adds data. You can turn off one key and keep the others. |
| **A Pebble Index ring** (optional) | It sends a note each time you hold it and talk. The Relay ring takes its place when it is ready. |

:::note
The Relay ring is still in design. [The ring](../../ring/how-it-works/) shows how it works and where it is now. Until it is ready, a Pebble Index ring sends the same notes.
:::

## The order

1. [Run your own Relay server](../run-your-own/), if you want to send.
2. [Install the app](../install/) on each phone.
3. To send, [connect each phone](../connect-a-phone/) to your Relay server with its own key.
4. [Set up the Pebble webhook](../pebble-webhook/), so ring notes go to Relay.
