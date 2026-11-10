# Relay Everything plugin for Claude Code and Codex

The Relay Everything plugin saves each Claude Code or Codex chat to your Relay Everything, and lets the AI read your notes, health, sleep, workouts, places, calendar and saved chats. One sign-in link connects the computer: you copy no key.

## Install in Claude Code

1. In Claude Code, type:

   ```text
   /plugin marketplace add matthewwong525/RelayEverything
   /plugin install relay@relay
   ```

2. Start Claude Code again.

## Install in Codex

1. In a terminal, type:

   ```text
   codex plugin marketplace add matthewwong525/RelayEverything
   codex plugin add relay@relay
   ```

2. Start Codex. It asks you to review the plugin's hooks. Pick **Trust all and continue**. Codex runs no hook that you did not trust, so with no trust it saves no chat. You can also trust the hooks later: type `/hooks` in Codex.
3. After an update that changes a hook, Codex asks again. Trust the hooks again.
4. The plugin's commands run outside Codex's sandbox, because in the sandbox they can not reach Relay Everything or write the plugin's folder. When Codex asks to run a plugin command outside the sandbox, approve it.

`codex exec` runs only hooks that you trusted in Codex before.

## Connect this computer

1. Type `/relay:connect` in Claude Code. In Codex, type `$relay:connect`, or ask *connect Relay Everything*.

   To use your own Relay Everything server, add its address: `/relay:connect https://<your-relay-server>`.
2. Open the link that the AI shows, on any phone or computer, and sign in.
3. Make sure that the page shows the same code as the AI. Then click **Connect**. The link works one time, for 10 minutes.
4. Tell the AI that you clicked **Connect**. The AI says the name of the computer.
5. If Claude Code or Codex also has the Relay Everything AI connector, the AI shows the command that removes it. The plugin does the same work. The AI runs the command only when you say yes.

One connection works for Claude Code and Codex on this computer.

If you used version 0.2 of the plugin, type `/relay:connect` one time. The old key only saves chats.

## Ask about your data

Ask in your own words, for example *how did I sleep last night?*, *find my notes about the battery*, or *what was I doing when I wrote the battery note?* The AI uses the plugin's `ask` skill. Times are in this computer's time zone, unless you name a different zone.

- **Your topics come first.** When a chat starts, the AI gets your top-level topics, one line each, from this computer's copy of your knowledge web. When your message names a topic, the AI gets that topic's summary. Both read only the copy on this computer: no network call, and the chat never waits. The copy syncs on its own when a chat starts, at most once in 15 minutes.
- **One step pulls a topic.** `relay.mjs topic battery` gets the page, the topics it links and those that link it, the newest facts and notes on it, and the chats its facts came from.
- **One step reads around a moment.** `relay.mjs around <note id>`, or `--at <time>`, gets the note, its day, and the notes, places, calendar events and hourly steps and heart rate from 2 hours before to 2 hours after. `--hours` sets the window, up to 12 hours each way.
- **The route of a stay or a trip.** `relay.mjs points <id>` gets its location points.

To add a note, ask *note in Relay Everything that …*.

## A database for your agents

Your agents get a database of their own, apart from your notes, health and places. An agent can make any table there and keep its own data, such as a reading list or a plan. Only this computer and your other connected computers reach it, and deleting your account deletes it.

- `relay.mjs db "<sql>"` runs one SQLite command; `--params '["Dune"]'` gives its `?` values.
- `relay.mjs db --file plan.sql` runs a file's commands, each ending with `;`, all or none.
- `relay.mjs db tables` lists the tables, their columns and how many rows each holds.

A command is at most 100 KB, 50 commands go in one step, an answer is at most 5,000 rows and 5 MB, and the database is at most 1 GB. Your notes, health, places, chats and facts are not in it, so no command can change them.

## Save a chat

Type `/relay:save` in Claude Code, or `$relay:save` in Codex, or ask *save this to Relay Everything*. The AI writes a title and a summary of what you decided and why. Relay Everything keeps them beside the chat.

## Turn saving off

- In one project: type `/relay:saving off`. Type `/relay:saving on` to save again, or `/relay:saving` to see which it is and when the project last sent a chat. This works for Claude Code and Codex.
- A git worktree counts as its main repository. Saving off holds in each workspace copy of the project, new ones too, and each chat there shows under the project's name.
- For one run: start the app with `RELAY_SAVE=0`, for example `RELAY_SAVE=0 claude` or `RELAY_SAVE=0 codex`.

To delete a chat from Relay Everything, open it on your Relay Everything page and click **Delete**. If the chat is still open, turn saving off first. If you do not, the plugin sends it again with your next message.

## What is sent

After each answer, the plugin sends the new messages of the chat to your Relay Everything:

- each message that you typed, and each answer that the AI wrote, word for word.
- one line for each step of the AI, such as `Ran: npm test` or `Edited src/app.ts`. It never sends the output of the step.
- the name of the project folder (for a git worktree, the name of its main repository), the title of the chat, the times, and the app: Claude Code or Codex.

The plugin never sends the thinking of the AI, the contents of a file, the output of a command, or the chat of a helper agent. Before a message goes from your computer, the plugin replaces keys, tokens, and each value of 8 or more characters in the `.env` and `.dev.vars` files of the project, with `[hidden]`.

A chat that ended before you connected the computer is not sent.

## What stays on this computer

The plugin keeps its files in `~/.config/relay-everything/`, or in `$XDG_CONFIG_HOME/relay-everything/` if you set `XDG_CONFIG_HOME`. To use a different folder, set `RELAY_EVERYTHING_HOME`.

- `computer.json` holds the server address, the key and the name of this computer. Only you can read it. Never copy the key into a chat or a file.
- The `state/` folder holds the path of each chat file, its project, how many messages were sent, the projects with saving off, and `send.log`. `send.log` holds the last 200 sends, with only session IDs, counts and statuses. A send that fails waits there, and the next start of the app sends it.
- The `knowledge/` folder is this computer's copy of your knowledge web: a git folder of topic pages. `knowledge.mjs sync` gets the newest pages and sends your changes, at most once every 15 minutes unless the copy has changes or you add `--now`. `knowledge.json` holds the time of the last sync. The one-hour pass for each sync goes to git only in its environment: it is never written to a file. The knowledge web needs git, and a server whose Cloudflare account has Artifacts.

## Disconnect this computer

1. Ask the AI to *forget the Relay Everything key*. It runs `connect.mjs forget`, which deletes `computer.json`.
2. To stop the key for all time, open **Devices** on your Relay Everything page, and click **Turn off** for this computer.
