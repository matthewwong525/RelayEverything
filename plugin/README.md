# Relay Everything for Claude Code and Codex

Relay Everything saves each Claude Code or Codex chat in a project to your Relay Everything, and lets the AI read your notes, health, sleep, workouts, places, calendar and saved chats. It installs as your own copy in each project: every file is yours to change, and git keeps it with the rest of your project. One sign-in link connects the computer: you copy no key.

## Install in a project

Open Claude Code or Codex in the project, and paste:

```text
Install Relay Everything in this project: follow https://relayeverything.com/install/
```

The AI gets the newest release, `relay-v<version>` in this repository, and runs its `install.mjs --into <project>`:

```text
your-project/
  .agents/relay/                 Relay Everything, yours to change
    RELEASE                      the release the copy came from
  .claude/skills/relay-<name>    links to .agents/relay/skills/<name>
  .agents/skills/relay-<name>    the same, for Codex
  .claude/settings.json          + Relay Everything's hooks
  .codex/hooks.json              + the same, for Codex
```

- The install keeps your own hooks, skills and settings. A skill name that another skill has is skipped, and the install says so.
- A project that has the copy changes nothing on a second install: it says to type `/relay-update`.
- In Codex, trust the project when it asks, so its hooks run. Codex runs no hook that you did not trust, and says nothing, so with no trust it saves no chat. To trust the hooks later, type `/hooks` in Codex.
- The skills' commands run outside Codex's sandbox, because in the sandbox they can not reach Relay Everything or write this computer's Relay Everything folder. When Codex asks, approve it.

`codex exec` runs only hooks that you trusted in Codex before.

## Update

Type `/relay-update` (`$relay-update` in Codex). It gets the newest release, shows what it changes, and merges it with your own edits:

- a file only the release changed takes the release's text;
- a file only you changed keeps yours;
- a file you both changed merges, and where you both changed the same lines, the AI shows both and asks: keep yours, the release's, or both.

Nothing changes until you say yes. Then `update.mjs apply` writes the files, `RELEASE`, a link for each new skill and the new hooks. Commit the result as you like.

## Saving is per project

A project with the copy saves its chats. A project with no copy and no plugin saves nothing; the Relay Everything plugin keeps saving it until you remove the plugin. One sign-in on a computer serves every project that has the copy.

## From the plugin

Version 0.7.0 of the Relay Everything plugin is the last. It says once that Relay Everything moved. Say *move Relay Everything here*, or type `/relay:move`, and it installs the copy in the project, keeps this computer's connection, and on your yes removes the plugin from Claude Code and Codex. In a project that has the copy, the plugin sends nothing, so no chat is sent twice.

## Connect this computer

1. Type `/relay-connect` in Claude Code. In Codex, type `$relay-connect`, or ask *connect Relay Everything*.

   To use your own Relay Everything server, add its address: `/relay-connect https://<your-relay-server>`.
2. Open the link that the AI shows, on any phone or computer, and sign in.
3. Make sure that the page shows the same code as the AI. Then click **Connect**. The link works one time, for 10 minutes.
4. Tell the AI that you clicked **Connect**. The AI says the name of the computer.
5. If Claude Code or Codex also has the Relay Everything AI connector, the AI shows the command that removes it. Relay Everything's skills do the same work. The AI runs the command only when you say yes.
6. The AI asks *Also remember things for you?* Say yes to turn on memory, or no to keep it off. You can change it later: [Memory](#memory).

One connection works for Claude Code and Codex on this computer.

If you used version 0.2 of the plugin, type `/relay-connect` one time. The old key only saves chats.

## Memory

Memory is off until you say yes at `/relay-connect`. Type `/relay-memory on` to turn it on, `/relay-memory off` to turn it off, or `/relay-memory` to see which it is. A computer that you connected before version 0.6.0 has memory off.

- **What it saves.** When a chat ends, your own AI reads it in the background and keeps short facts: who you are, how you want a job done, what you decided or plan, where to find a thing, and what is still open. It keeps a copy of the chat's transcript with keys hidden, so a fact can show where it came from.
- **Where.** The facts and transcripts go to your own Relay Everything space, with this computer's key. They do not go to a webhook.
- **What a chat gets.** A chat starts with your open threads, your newest facts and your topics. A message that names a topic gets its summary. Ask *what did we decide about …*, or type `/relay-memory`, to search it.
- **A project's own memory wins.** In a project that has its own memory, such as a WongStack project (`.claude/skills/memory/` or `.agents/memory/profile.mjs`), Relay Everything's memory stays off. Relay Everything still saves the chat there, and shows no topics.
- **Look-up counts stay on this computer.** Memory counts each look-up in a file on this computer and keeps each count for 30 days. For a question that got no good answer, it also keeps the words of the question. Each chat start deletes counts older than 30 days. The counts never leave this computer.
- **It stays off** where saving is off, with `RELAY_SAVE=0`, and in a folder that is not a git project.
- **One daily job.** Memory starts no daily job of its own. The daily build stays the one job each day, and it leaves out a chat that memory read.

## Ask about your data

Ask in your own words, for example *how did I sleep last night?*, *find my notes about the battery*, or *what was I doing when I wrote the battery note?* The AI uses the `relay-ask` skill. Times are in this computer's time zone, unless you name a different zone.

- **Your topics come first.** With memory off, when a chat starts, the AI gets your top-level topics, one line each, from this computer's copy of your knowledge web. When your message names a topic, the AI gets that topic's summary. Both read only the copy on this computer: no network call, and the chat never waits. The copy syncs on its own when a chat starts, at most once in 15 minutes.
- **One step pulls a topic.** `relay.mjs topic battery` gets the page, the topics it links and those that link it, the newest facts and notes on it, and the chats its facts came from. With memory on, it gives memory's pull of the topic, then its notes and chats.
- **One step reads around a moment.** `relay.mjs around <note id>`, or `--at <time>`, gets the note, its day, and the notes, places, calendar events and hourly steps and heart rate from 2 hours before to 2 hours after. `--hours` sets the window, up to 12 hours each way.
- **The route of a stay or a trip.** `relay.mjs points <id>` gets its location points.

To add a note, ask *note in Relay Everything that …*.

## A database for your agents

Your agents get a database of their own, apart from your notes, health and places. An agent can make any table there and keep its own data, such as a reading list or a plan. Only this computer and your other connected computers reach it, and deleting your account deletes it.

- `relay.mjs db "<sql>"` runs one SQLite command; `--params '["Dune"]'` gives its `?` values.
- `relay.mjs db --file plan.sql` runs a file's commands, each ending with `;`, all or none.
- `relay.mjs db tables` lists the tables, their columns and how many rows each holds.

A command is at most 100 KB, 50 commands go in one step, an answer is at most 5,000 rows and 5 MB, and the database is at most 1 GB. Your notes, health, places, chats and facts are not in it, so no command can change them.

## Your web builds itself

Once a day, your own AI builds your memory and your knowledge web. The first chat of the day on a connected computer starts `build.mjs run` in the background, and the chat does not wait. The build runs in the app the chat started in, Claude Code or Codex, on your own plan and allowance. It stops after 30 minutes.

- Helpers read the newest unread chats and notes first: at most 20 chats and 100 notes a day. A chat is read when it has been quiet for an hour. A chat that grew is read again from where the last read stopped.
- Each helper checks the facts you have before it adds one: new, changed (it replaces the old one), or the same (it adds nothing). It gives each note its topics, and never changes the note's words.
- A last helper writes the topic pages side by side, links the topics that connect, and keeps `README.md` current.
- The web's `.relay/` folder records what was read and which computer built each day. With two computers, only the first to claim the day builds.
- The build's AI can run only `build.mjs`, which has no health, place, calendar or photo command. Its hooks are off, so its own chat is not saved.

Type `/relay-build` (`$relay-build` in Codex) to see the last build and what is still to read. `/relay-build off` stops the daily build on this computer, `/relay-build on` starts it again, and `/relay-build now` starts one at once. Set `RELAY_BUILD_MODEL` to use another model for the build, such as `RELAY_BUILD_MODEL=haiku`.

## Save a chat

Type `/relay-save` in Claude Code, or `$relay-save` in Codex, or ask *save this to Relay Everything*. The AI writes a title and a summary of what you decided and why. Relay Everything keeps them beside the chat.

## Turn saving off

- In one project: type `/relay-saving off`. Type `/relay-saving on` to save again, or `/relay-saving` to see which it is and when the project last sent a chat. This works for Claude Code and Codex.
- A git worktree counts as its main repository. Saving off holds in each workspace copy of the project, new ones too, and each chat there shows under the project's name.
- For one run: start the app with `RELAY_SAVE=0`, for example `RELAY_SAVE=0 claude` or `RELAY_SAVE=0 codex`.

To delete a chat from Relay Everything, open it on your Relay Everything page and click **Delete**. If the chat is still open, turn saving off first. If you do not, Relay Everything sends it again with your next message.

## What is sent

After each answer, Relay Everything sends the new messages of the chat to your Relay Everything:

- each message that you typed, and each answer that the AI wrote, word for word.
- one line for each step of the AI, such as `Ran: npm test` or `Edited src/app.ts`. It never sends the output of the step.
- the name of the project folder (for a git worktree, the name of its main repository), the title of the chat, the times, and the app: Claude Code or Codex.

Relay Everything never sends the thinking of the AI, the contents of a file, the output of a command, or the chat of a helper agent. Before a message goes from your computer, Relay Everything replaces keys, tokens, and each value of 8 or more characters in the `.env` and `.dev.vars` files of the project, with `[hidden]`.

A chat that ended before you connected the computer is not sent.

## What stays on this computer

The copy in a project holds no key, chat or state. Relay Everything keeps them for the whole computer in `~/.config/relay-everything/`, or in `$XDG_CONFIG_HOME/relay-everything/` if you set `XDG_CONFIG_HOME`. To use a different folder, set `RELAY_EVERYTHING_HOME`.

- `computer.json` holds the server address, the key, the name of this computer and your memory choice. Only you can read it. Never copy the key into a chat or a file.
- The `state/` folder holds the path of each chat file, its project, how many messages were sent, the projects with saving off, and `send.log`. `send.log` holds the last 200 sends, with only session IDs, counts and statuses. A send that fails waits there, and the next start of the app sends it.
- With memory on, memory keeps its own files for each project in the project's git folder, in `.git/wong-memory/`: the chats it knows, facts that wait for the network, and the last start's summary.
- The `knowledge/` folder is this computer's copy of your knowledge web: a git folder of topic pages. `knowledge.mjs sync` gets the newest pages and sends your changes, at most once every 15 minutes unless the copy has changes or you add `--now`. `knowledge.json` holds the time of the last sync. The one-hour pass for each sync goes to git only in its environment: it is never written to a file. The knowledge web needs git, and a server whose Cloudflare account has Artifacts.

- `build.json` holds the daily build's settings for this computer: off or on, the day of the last try, a random id for this computer, what is still to read, and the last error. The `build/` folder holds a lock while a build runs, and the run's counts, ids and topic names, which the next build clears.

## Disconnect this computer

1. Ask the AI to *forget the Relay Everything key*. It runs `connect.mjs forget`, which deletes `computer.json`.
2. To stop the key for all time, open **Connect your AI** on your Relay Everything page, and click **Disconnect** for this computer.
