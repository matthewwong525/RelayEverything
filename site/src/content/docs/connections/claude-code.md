---
title: Save AI chat transcripts
description: Save each Claude Code and Codex chat to your Relay Everything server with the Relay Everything plugin, ask about your data from the chat, and find your chats on your Relay Everything page.
---

The Relay Everything plugin for Claude Code and Codex saves each chat to your Relay Everything server as you talk. You find a chat on the Relay Everything page by a word, and your AI can search it through the [AI connector](../connect-your-ai/). The plugin also lets the AI in the chat read your notes, health, places and calendar, and add a note, when you ask it. Once a day, your own AI builds your knowledge web from your chats and notes.

## Install the plugin

Do the steps for each app you use. One computer needs one connect, for both apps.

**In Claude Code:**

1. Type these two commands:

   ```text
   /plugin marketplace add matthewwong525/RelayEverything
   /plugin install relay@relay
   ```

2. Start Claude Code again.

**In Codex:**

1. In a terminal, run these two commands:

   ```text
   codex plugin marketplace add matthewwong525/RelayEverything
   codex plugin add relay@relay
   ```

2. Start Codex. It asks you to review the plugin's hooks: pick **Trust all and continue**. Codex runs no hook that you did not trust, and says nothing, so with no trust it saves no chat. To trust the hooks later, type `/hooks` in Codex.
3. After an update that changes a hook, Codex asks again. Trust the hooks again.
4. The plugin's commands run outside Codex's sandbox, because in the sandbox they can not reach Relay Everything or write the plugin's folder. When Codex asks to run a plugin command outside the sandbox, approve it.

## Connect the computer

1. Type `/relay:connect` in Claude Code, or `$relay:connect` in Codex. To use [your own Relay Everything server](../../start/run-your-own/), add its address: `/relay:connect https://<your-relay-server>`.
2. The AI shows a link and a code, such as `KITE-4821`. Open the link, and sign in to Relay Everything if it asks.
3. Make sure that the page shows the same code. Then click **Connect**. Connect only a computer that you just started this on. If someone sent you the link, click **Cancel**.
4. Tell the AI that you clicked **Connect**. It says when the computer is connected.

The computer now has its own key, kept in a file that only you can read on that computer: `computer.json` in `~/.config/relay-everything/`, or in the folder that `RELAY_EVERYTHING_HOME` names. It shows under **Claude Code and Codex** in **Connect your AI**, on your Relay Everything page and in the app, with when it last saved a chat. The key saves chats, and reads and adds through the [web API](../../api/connect-a-service/). Each chat from then on is saved. Chats from before the connect are not sent.

If you added the AI connector to Claude Code or Codex before, the connect step names it and how to remove it, because the plugin does the same job. It removes nothing unless you say so.

## Ask about your data

Ask in plain words, such as *what did I note about the charger?*, *how did I sleep last week?* or *what was I doing when I wrote the battery note?* The AI reads your Relay Everything data through the plugin. Ask *note that the charger needs a new cable*, and it adds a note.

The AI also reads and adds to your memory of facts, and keeps a copy of your knowledge web on the computer, in `knowledge/` in `~/.config/relay-everything/`: [Memory and knowledge web](../../api/knowledge-web/). It can keep its own tables in [your agents' database](../../api/agents-database/).

**The AI starts from your topics.** When a chat starts, the AI gets your top-level topics, one line each, from the copy on your computer:

```text
Relay Everything topics, from your knowledge web:
battery  Stays 40 mAh; charger cable open
bike     Commuter bike: lights, lock, tires
sam      Friend from the bike club
```

When your message names a topic, such as *is the battery still 40 mAh?*, the AI also gets that topic's summary. Both read only the copy on your computer, so the chat never waits for the network. The copy syncs on its own when a chat starts, at most once in 15 minutes.

**One step pulls a topic.** The AI gets the topic's page, the topics it links and those that link it, its newest facts and notes, and up to 3 saved chats that its facts came from. From there it opens a fact's source.

**One step reads around a moment.** Ask about a note, and the AI reads its day, and the notes, places, calendar events and hourly steps and heart rate from 2 hours before to 2 hours after:

```text
You: what was going on when I wrote the battery note?
AI:  You wrote it at 14:20 at the workshop, 20 minutes after
     "Bike fitting" on your calendar. You walked 6,100 steps that
     day. A saved chat on Nov 3 talks about the same battery.
```

The AI can also read the route of a stay or a trip, such as *which way did I walk to the station?*

## Your web builds itself

Once a day, your own AI builds your memory and your knowledge web on this computer. The first chat of the day starts the build in the background, and your chat never waits. You pick nothing: no topic, no tag.

- **Helpers read your chats and notes.** A chat is read when it has been quiet for an hour, so the chat you are in waits for tomorrow. A chat that grew is read again from where the last read stopped. Each helper adds short facts, each with its topics and a link to the message or note it came from. Before it adds a fact, it looks at the facts you already have: it adds a new one, replaces an old one that changed, or adds nothing.
- **Your notes get topics.** Your words stay as you wrote them.
- **A helper writes your topic pages, side by side.** It sums up each topic's facts, splits a big topic into smaller linked pages, links topics that share a fact, a note or a chat, and keeps `README.md` current. When it makes a new topic, it looks back for older facts and notes that fit.
- **Your past fills in a part each day.** Each build reads the newest unread chats and notes first: at most 20 chats and 100 notes. A record of what was read stays in your web, in `.relay/`, so nothing is read twice, on any of your computers.
- **One computer builds each day.** With two computers, the first to claim the day in your web builds, and the other stops.
- **Health and places stay where they are.** The build has no command that reads your health, places, calendar or photos. A note's place does not reach it. A page links the day, and the AI reads that day only when you ask.

The build runs in the app the chat started in, Claude Code or Codex, on your own plan: it uses your allowance, as a chat does. It stops after 30 minutes, and the next day goes on from what it read. To use a smaller model for it, set `RELAY_BUILD_MODEL`, such as `RELAY_BUILD_MODEL=haiku`. The build's own chat is not saved.

Type `/relay:build` (`$relay:build` in Codex) to see the last build:

```text
The daily build is on for this computer: it starts with the first chat of each day.
Last build: 2026-11-10 09:14, on Laptop
  12 chats, 40 notes read
  18 facts added, 3 replaced
  2 new topics: garden, sam
Still to read: 31 chats, 220 notes
```

`/relay:build off` stops the daily build on this computer, `/relay:build on` starts it again, and `/relay:build now` starts one at once. Facts and topics that a build added stay when you turn it off.

## Save a summary

Type `/relay:save` in Claude Code or `$relay:save` in Codex, or ask *save this to Relay Everything*. The AI writes a title and a summary of what you decided, and keeps it beside the chat.

## What is sent

After each answer, the plugin sends the chat's new messages:

- each message you typed, and each answer the AI wrote, word for word;
- one line for each step the AI took, such as `Ran: npm test` or `Read src/app.ts`, never the step's output;
- the app, the project's folder name (for a git worktree, its main repository's name), the chat's title and the times.

It never sends the AI's thinking, a file's contents, a command's output or a helper's own chat. Before a message leaves your computer, the plugin replaces keys and tokens, and each value of 8 characters or more in the project's `.env` and `.dev.vars`, with `[hidden]`.

A send that fails waits on your computer, and the next start of the app sends it.

## Read your chats

On the Relay Everything page, click **Connect your AI**, under **Other connections** in the left bar, then **Saved chats**. It lists your chats, newest first, each with its app. Type words in its search to find the chats that hold all of them. Open a chat to read it: the AI's saved summary shows at the top, marked *Written by the AI*, and each step shows as a grey line.

In the app, tap **Connect your AI** on Home, then **Saved chats**. Signed in, **Read them on the web** opens them on your Relay Everything page.

Your AI can search the chats too: the [AI connector](../connect-your-ai/) has the tools `search_chats` and `read_chat`.

## Turn saving off

- **In one project:** type `/relay:saving off` (`$relay:saving off` in Codex). Type `/relay:saving on` to save again, or `/relay:saving` to see which it is and when the project last sent a chat. A git worktree counts as its main repository, so saving off holds in each workspace copy of the project, new ones too.
- **For one run:** start the app with `RELAY_SAVE=0`, such as `RELAY_SAVE=0 claude` or `RELAY_SAVE=0 codex`.
- **On one computer:** click **Disconnect** beside it, in **Connect your AI** on your Relay Everything page. To also delete the key from the computer, ask the AI to *forget the Relay Everything key*.

## Delete a chat

Open the chat on the Relay Everything page, click **Delete**, then confirm. Relay Everything removes the chat, its messages and the AI's summary. You can't undo it. If the chat is still open, turn saving off first, or the plugin sends it again with your next message.

## What the server receives

The plugin calls two routes with the computer's key in the header `Authorization: Bearer rek_…`.

`POST https://<your-relay-server>/apps/relay/api/chats` adds a chat's new messages:

```json
{
  "sessionId": "5d1c2b7a-0e4f-4a6b-9c3d-8e7f6a5b4c3d",
  "app": "codex",
  "project": "my-app",
  "startedAt": 1793800800000,
  "title": "Why does the sign-in test fail?",
  "messages": [
    { "seq": 0, "role": "you", "text": "Why does the sign-in test fail?", "at": 1793800800000 },
    { "seq": 1, "role": "step", "text": "Read tests/sign-in.test.ts", "at": 1793800830000 },
    { "seq": 2, "role": "ai", "text": "The test expects the old button name.", "at": 1793800860000 }
  ]
}
```

- `app` is `claude-code` or `codex`. With no `app`, the chat is a Claude Code chat.
- `role` is `you`, `ai` or `step`. `seq` counts from `0` in each chat, and `at` is milliseconds since 1970.
- The answer is only `{ "stored": 3 }`: how many messages the server holds for this chat.
- A message the server holds already is kept as it was. A repeat changes nothing, and the chat's app, title, project and start stay as the first send gave them.
- When the first `seq` is past `stored`, the answer is `400` with `stored`. Send again from there.
- Send at most 500 messages and 4 MB at a time, and at most 200,000 characters in one message. A larger send answers `413` and stores nothing.

`POST https://<your-relay-server>/apps/relay/api/chat-saves` adds the AI's summary to a chat this key sent: `{ "sessionId": "...", "title": "Sign-in test fix", "text": "Rename the button in the test." }`. The answer is `{ "ok": true }`, or `404` when this key sent no chat with that `sessionId`.

On the server, the computer's key gets `403` on every other route except `GET key`. Only a signed-in person can list, read or delete chats here: [Routes](../../api/reference/) shows each one. The key reads your chats through the [web API](../../api/connect-a-service/) instead.

## The computer's sign-in

`/relay:connect` uses three routes, which need no key:

1. `POST https://<your-relay-server>/apps/relay/sign-in/computer/start` with `{ "challenge": "<SHA-256 of a new secret, base64url>", "name": "My laptop" }` answers `{ "link": "…", "words": "KITE-4821" }`. The link lasts 10 minutes.
2. The person opens the link, signs in, and clicks **Connect**.
3. `POST https://<your-relay-server>/apps/relay/sign-in/computer/key` with `{ "verifier": "<the secret>" }` answers `202` with `{ "waiting": true }` until the person clicks **Connect**. Then it answers `{ "server": "…", "key": "rek_…", "api": "…/v1", "name": "My laptop" }`, once.
