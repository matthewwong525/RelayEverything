---
title: Connect your AI
description: Let the Claude app, ChatGPT or Claude Code read your Relay Everything notes, health, calendar, places and chats, and add notes, with one connector address and your own sign-in.
---

Relay Everything's AI connector lets an AI chat app read your Relay Everything data when you ask it a question, and add a note when you ask it to save one. It can't change or delete anything. Each person with a Relay Everything account can connect their own apps, and each app reads only that person's own space.

The connector's address is on the **AI apps** card at the bottom of the Relay Everything page, with a **Copy** button. It looks like `https://<your-relay-server>/mcp`.

## Connect an app

You connect each app one time. Each app opens a sign-in page: click **Connect**, then sign in to Relay Everything the way you sign in to your page: an email code, Apple or Google, or your own server's login.

- **The Claude app** (web, desktop or phone): open **Settings → Connectors → Add custom connector**. Type `Relay Everything` as the name and paste the address. Click **Connect**, then sign in. On a new chat, turn Relay Everything on in the tools menu.
- **ChatGPT**: open **Settings → Apps & Connectors → Advanced settings** and turn on **Developer mode**. Then click **Create**, type `Relay Everything`, paste the address and pick **OAuth** for the sign-in. Click **Create**, then sign in. In a chat, pick Relay Everything from the developer-mode tools.
- **Claude Code**: run `claude mcp add --transport http relay <address>`, then type `/mcp` in Claude Code and pick `relay` to sign in. With the [Relay Everything plugin](../claude-code/), type `/relay:connect-ai <address>` instead.

Then ask, for example: *What did I note on 4 November?*, *What is on my day?* or *When did I last meet Sam?*

## What the AI can read and add

The connector has ten tools. Nine only read, and one adds a note. Each tool reaches only the space of the person who connected the app. Each answer has a limit, so one question can't copy all of your space.

- **search**: notes that hold every word you give, newest first.
- **fetch**: one note, the places near it in time, and its day's health totals.
- **timeline**: every note from one time to another, a page at a time.
- **day_summary**: one day's notes count, health totals, places and events, with each event's title, times and people.
- **health**: one health type, such as steps, sleep, weight or blood pressure, one value per hour or per day. [Health](../../app/health/#what-it-reads) lists the types.
- **calendar**: the events from one time to another, with title, times, place, notes and people. Give words to find events that hold them, newest first, such as a person's name. [Calendar](../../app/calendar/)
- **places**: each stay at a place, with when you arrived and left.
- **search_chats**: [saved Claude Code chats](../claude-code/) that hold every word you give, with the lines that match.
- **read_chat**: one saved chat, a part at a time, with the AI's saved summary.
- **add_note**: adds a typed note, with the app's name as its device. It goes to your [webhooks](../your-database/) that take notes, as a phone's note does. The app sends its own id with each note, so a resend is kept once.

An app you connected before the connector could add notes still reads. To let it add, disconnect it and connect it again.

The same sign-in opens the web API, for your own scripts and services: [Connect a service](../../api/connect-a-service/).

## What leaves Relay Everything

When an app uses a tool, the answer goes to that app's company: Anthropic for Claude, OpenAI for ChatGPT. Their own terms then apply to it. An answer can hold a note's words, its time, the place name and coordinates, the device name, health totals, calendar events with their people, and a chat's messages.

An answer never holds a recording, a device key, or a device's or delivery's id. The app gets only what a tool answers for one question, not a copy of your data.

## Disconnect an app

On the Relay Everything page, find the app in the **AI apps** card and click **Disconnect**, then confirm. The card lists only the apps you connected. Its sign-in stops at once: its next question gets a refusal. The notes it added stay. To use it again, connect it again from the app. Removing Relay Everything in the app's own settings does not end the sign-in on Relay Everything's side.
