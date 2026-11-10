---
title: Connect your AI
description: Let the Claude app, ChatGPT, Claude Code or Codex read your Relay Everything notes, health, sleep, workouts, calendar, places, chats and photos, and add notes, with one connector address and your own sign-in.
---

Relay Everything's AI connector lets an AI chat app read your Relay Everything data when you ask it a question, and add a note when you ask it to save one. It can't change or delete anything. Each person with a Relay Everything account can connect their own apps, and each app reads only that person's own space.

The connector's address is on the **AI apps** page of Settings, on your Relay Everything page, with a **Copy** button. On the shared server it is `https://mcp.relayeverything.com`. `https://mcp.relayeverything.com/mcp` also works. Your own server's connector has its own address, such as `https://<your-relay-server>`.

## Connect an app

You connect each app one time. Each app opens a sign-in page: click **Connect**, then sign in to Relay Everything the way you sign in to your Relay Everything page: an email code, Apple or Google, or your own server's login.

- **The Claude app** (web, desktop or phone): open **Settings → Connectors → Add custom connector**. Type `Relay Everything` as the name and paste the address. Click **Connect**, then sign in. On a new chat, turn Relay Everything on in the tools menu.
- **ChatGPT**: open **Settings → Apps & Connectors → Advanced settings** and turn on **Developer mode**. Then click **Create**, type `Relay Everything`, paste the address and pick **OAuth** for the sign-in. Click **Create**, then sign in. In a chat, pick Relay Everything from the developer-mode tools.
- **Claude Code and Codex**: use the [Relay Everything plugin](../claude-code/) instead of the connector. It reads the same data, adds notes and saves your chats, with one `/relay:connect`. If you added the connector before, remove it, so the AI does not see each tool two times.

Then ask, for example: *What did I note on 4 November?*, *What is on my day?*, *When did I last meet Sam?* or *Show me the photos from the trip to Lisbon.*

## What the AI can read and add

The connector has fourteen tools. Thirteen only read, and one adds a note. Each tool reaches only the space of the person who connected the app. Each answer has a limit, so one question can't copy all of your space.

- **search**: notes that hold every word you give, newest first.
- **fetch**: one note, the places you stayed near it in time, and its day's health totals.
- **timeline**: every note from one time to another, a page at a time.
- **day_summary**: one day's notes count, health totals, nights of sleep, workouts, places, trips and events. Each place is a stay with its name and times; each trip has its mode, km and minutes; each event has its title, times and people.
- **health**: one health type, such as steps, sleep, weight or blood pressure, one value per hour or per day. [Health](../../app/health/#what-it-reads) lists the types.
- **nights**: each night of sleep, newest first: when you went to bed, fell asleep and woke, and the minutes in core, deep and REM sleep and awake. Ask for the stages to get each night's stage timeline.
- **workouts**: each workout, newest first, with its kind, such as running, its minutes, km and calories.
- **calendar**: the events from one time to another, with title, times, place, notes and people. Give words to find events that hold them, newest first, such as a person's name. [Calendar](../../app/calendar/)
- **places**: each stay at a place, with its name, street, and when you arrived and left, and each trip between two stays: walking, running, cycling, driving or flying, with its km and minutes. So *Where did I go on Saturday?* gets one short answer. Days from before your phone made stays give each street, as before. [Location](../../app/location/)
- **search_chats**: [saved AI chats from Claude Code and Codex](../claude-code/) that hold every word you give, with the lines that match.
- **read_chat**: one saved chat, a part at a time, with the AI's saved summary.
- **photos**: the [photos your phones sent](../../app/photos/) from one time to another, newest first, with when and where you took each one. It can show only the photos near a place, up to 500 km. It lists at most 50 photos a page.
- **read_photo**: one photo, as an image the AI can look at, with when and where you took it.
- **add_note**: adds a typed note, with the app's name as its device. It goes to your [webhooks](../your-database/) that take notes, as a phone's note does. The app sends its own id with each note, so a resend is kept once.

An app you connected before the connector could add notes still reads. To let it add, disconnect it and connect it again.

The same sign-in opens the web API, for your own scripts and services: [Connect a service](../../api/connect-a-service/).

## What leaves Relay Everything

When an app uses a tool, the answer goes to that app's company: Anthropic for Claude, OpenAI for ChatGPT. Their own terms then apply to it. An answer can hold a note's words, its time, the place name and coordinates, the device name, health totals, nights of sleep with their stages, workouts, calendar events with their people, a chat's messages, and a photo with its time and place.

An answer never holds a recording, a device key, or a device's or delivery's id. The app gets only what a tool answers for one question, not a copy of your data.

## Disconnect an app

On the Relay Everything page, open **Settings**, then **AI apps**. Find the app and click **Disconnect**, then confirm. The page lists only the apps you connected. Its sign-in stops at once: its next question gets a refusal. The notes it added stay. To use it again, connect it again from the app. Removing Relay Everything in the app's own settings does not end the sign-in on Relay Everything's side.
