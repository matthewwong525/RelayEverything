---
name: relay-connect
description: Connect this computer to Relay Everything by a sign-in link, so Claude Code and Codex save chats and can read the person's Relay Everything. Use for /relay-connect, "connect Relay Everything", "connect this computer to Relay Everything", or when a Relay Everything step says to connect.
argument-hint: "[server address]"
allowed-tools: Bash(node:*)
---

# Connect this computer to Relay Everything

Each command runs Relay Everything's copy in this project, `.agents/relay/`. When that folder is missing, this is the Relay Everything plugin: in each command, put the folder two levels above this file in place of `$(git rev-parse --show-toplevel)/.agents/relay`. Never install the copy unless the person asks: `/relay:move` moves it into this project. In Codex, put the person's words in place of `$ARGUMENTS`.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it. In Codex's sandbox, the command can not reach the network or write this computer's Relay Everything folder.

1. Start. Add the server address only if the person gave one; with none, it connects to Relay Everything's own server.

   ```bash
   node "$(git rev-parse --show-toplevel)/.agents/relay/bin/connect.mjs" start $ARGUMENTS
   ```

2. Show the person the lines it prints, word for word: a link and a code. Ask them to open the link on any phone or computer, check that the code is the same, click **Connect**, and then tell you. Do not run anything else until they answer.
3. Wait for the key. It waits up to 90 seconds.

   ```bash
   node "$(git rev-parse --show-toplevel)/.agents/relay/bin/connect.mjs" wait
   ```

   If it says *Not connected yet*, ask the person to click **Connect**, then run `wait` again.
4. Show the lines it prints, word for word. A line can name a second Relay Everything AI connector with a command that removes it. Ask the person before you run that command, and never run it unasked.
5. When it says *connected*, ask the person: *Also remember things for you?* Say in one line what it does: Relay Everything keeps short facts from each chat on this computer, such as what they decided, prefer and left open, in their own Relay Everything space, and each new chat starts with them. A project with its own memory keeps its own. On a yes, run the first command; on a no, the second. Show the lines it prints, word for word.

   ```bash
   node "$(git rev-parse --show-toplevel)/.agents/relay/bin/connect.mjs" memory on
   node "$(git rev-parse --show-toplevel)/.agents/relay/bin/connect.mjs" memory off
   ```

Never show, print or copy the key. It stays in this computer's key file.

`status` says whether this computer is connected. `forget` deletes the key file. `/relay-memory on` or `off` changes the memory choice later.
