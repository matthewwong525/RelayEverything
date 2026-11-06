---
title: What you need
description: The server, phone and keys you need before you use Relay Everything, and an optional ring.
---

To take notes, you need only a phone with the Relay Everything app: the notes stay on it. To send them on, you also need a Relay Everything server and a key for each device. A ring to talk into is optional.

| What | Why |
|---|---|
| **A Relay Everything server** (to send) | It keeps the notes, health and places you send. You [run your own](../run-your-own/), in your own Cloudflare account, behind your own login. You make the keys. |
| **An iPhone or an Android phone** | The Relay Everything app shows your notes, and sends a typed note, your health and where you go. |
| **A key for each device** (to send) | Each phone and the Pebble app has its own key. A key only adds data. You can turn off one key and keep the others. |
| **A Pebble Index ring** (optional) | It sends a note each time you hold it and talk. The Relay Everything ring takes its place when it is ready. |

:::note
The Relay Everything ring is still in design. [The ring](../../ring/how-it-works/) shows how it works and where it is now. Until it is ready, a Pebble Index ring sends the same notes.
:::

## The order

1. [Run your own Relay Everything server](../run-your-own/), if you want to send.
2. [Install the app](../install/) on each phone.
3. To send, [connect each phone](../connect-a-phone/) to your Relay Everything server with its own key.
4. [Set up the Pebble webhook](../pebble-webhook/), so ring notes go to Relay Everything.
