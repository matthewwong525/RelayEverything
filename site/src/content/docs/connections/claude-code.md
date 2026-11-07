---
title: Save Claude Code chats
description: Save each Claude Code chat to your Relay Everything server with the Relay Everything plugin, find it on the Relay Everything page, and let your AI search it.
---

The Relay Everything plugin for Claude Code saves each chat to your Relay Everything server as you talk. You find a chat on the Relay Everything page by a word, and your AI can search it through the [AI connector](../connect-your-ai/). Ask *save this to Relay Everything*, and the AI also writes a title and a summary of what you decided, kept beside the chat.

## Make a connect code

You make one connect code for each computer, on your Relay Everything page: click **Add a device**, name it, such as `Laptop`, and pick Claude Code as its kind.

The code shows once. It is a [chat key](../../api/keys/#a-chat-key) that can only add chats to your own space. It can't read, change or delete anything.

To keep chats in your own Cloudflare account, [run your own Relay Everything server](../../start/run-your-own/) and make the code there. The plugin sends only to the server in the code: it has no address built in.

## Install the plugin

1. In Claude Code, add the plugin from the public Relay Everything repository:

   ```text
   /plugin marketplace add matthewwong525/RelayEverything
   /plugin install relay@relay
   ```

2. When Claude Code asks for the **Relay Everything connect code**, paste the code. Claude Code keeps it in your system's secure store.
3. Close the page that shows the code: it does not show again.

Chats from then on are saved. Chats from before the install are not sent.

## What is sent

After each answer, the plugin sends the chat's new messages:

- each message you typed, and each answer the AI wrote, word for word;
- one line for each step the AI took, such as `Ran: npm test` or `Read src/app.ts`, and for each `!` command you run, never the step's output;
- the project's folder name, the chat's title and the times.

It never sends the AI's thinking, a file's contents, a command's output or a helper's own chat. Before a message leaves your computer, the plugin replaces keys and tokens, and each value of 8 characters or more in the project's `.env` and `.dev.vars`, with `[hidden]`.

A send that fails waits on your computer, and the next start of Claude Code sends it.

## Read your chats

The **Chats** card on the Relay Everything page lists your chats, newest first. Type words in its search to find the chats that hold all of them. Open a chat to read it: the AI's saved summary shows at the top, marked *Written by the AI*, and each step shows as a grey line.

Your AI can search the chats too: the [AI connector](../connect-your-ai/) has the tools `search_chats` and `read_chat`.

## Turn saving off

- **In one project:** type `/relay:saving off` in Claude Code. Type `/relay:saving on` to save again, or `/relay:saving` to see which it is and when the project last sent a chat.
- **For one run:** start Claude Code with `RELAY_SAVE=0 claude`.
- **On one computer:** click **Turn off** beside its key on your Relay Everything page, or remove the plugin with `/plugin uninstall relay@relay`.

## Delete a chat

Open the chat on the Relay Everything page, click **Delete**, then confirm. Relay Everything removes the chat, its messages and the AI's summary. You can't undo it. If the chat is still open in Claude Code, turn saving off first, or the plugin sends it again with your next message.

## What the server receives

The plugin calls two routes with the chat key in the header `Authorization: Bearer rek_…`.

`POST https://<your-relay-server>/apps/relay/api/chats` adds a chat's new messages:

```json
{
  "sessionId": "5d1c2b7a-0e4f-4a6b-9c3d-8e7f6a5b4c3d",
  "project": "relay-ring",
  "startedAt": 1793800800000,
  "title": "How thick should the stiffener be?",
  "messages": [
    { "seq": 0, "role": "you", "text": "How thick should the stiffener be?", "at": 1793800800000 },
    { "seq": 1, "role": "step", "text": "Read pcb/relay.kicad_pcb", "at": 1793800830000 },
    { "seq": 2, "role": "ai", "text": "0.2 mm steel is enough for a ring this size.", "at": 1793800860000 }
  ]
}
```

- `role` is `you`, `ai` or `step`. `seq` counts from `0` in each chat, and `at` is milliseconds since 1970.
- The answer is only `{ "stored": 3 }`: how many messages the server holds for this chat.
- A message the server holds already is kept as it was. A repeat changes nothing, and the chat's title, project and start stay as the first send gave them.
- When the first `seq` is past `stored`, the answer is `400` with `stored`. Send again from there.
- Send at most 500 messages and 4 MB at a time, and at most 200,000 characters in one message. A larger send answers `413` and stores nothing.

`POST https://<your-relay-server>/apps/relay/api/chat-saves` adds the AI's summary to a chat this key sent: `{ "sessionId": "...", "title": "Stiffener plan", "text": "Use a 0.2 mm steel stiffener." }`. The answer is `{ "ok": true }`, or `404` when this key sent no chat with that `sessionId`.

A chat key gets `403` on every other route. Only a signed-in person can list, read or delete chats: [Routes](../../api/reference/) shows each one.
