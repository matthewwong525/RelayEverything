# The Relay Everything plugin starts from your topics, pulls a thread in one step, reads around a moment, and knows a project in every workspace

**Status:** planned
**Branch:** plugin-follows-threads
**Open questions:** none
**Builds on:** knowledge-web (part 1). Part 2, which fills the web, comes later; until then the web is empty and the topic hooks show nothing.

## Why

Your Relay Everything now has a memory of facts and a web of topic pages (part 1). But the AI does not know they are there unless it is told, and it does not know which topic fits a question. When you ask the AI about a note or a moment, it reads only the one thing you named. It does not look at what was around it: the day, the notes just before and after, where you were, what was on your calendar, or a chat on the same subject. So its answers miss the connections. It also can not read the route of a stay or a trip, though Relay Everything has it. And in a project that opens each chat in its own workspace copy, as WongOS does, the plugin names each chat by the copy (*rural-horse*), not *WongOS*, and *saving off* holds only for that one copy.

## What Changes

- **The AI sees your topics when a chat starts.** It gets the list of your top-level topics, one line each, from this computer's copy of your web. So it knows what it can pull before you ask. The copy syncs on its own, at most once in 15 minutes, and the chat never waits for it. In a project, the AI also gets that project's topic summary when one exists.
  ```text
  Relay Everything topics:
  battery   Stays 40 mAh; charger cable open
  ring      Bike ring v2: band, board, sync
  sam       Friend from the bike club
  ```

- **Your words bring in the topic they name.** Before the AI reads your message, the plugin looks for your topics' names in it, on this computer, with no network call. A clear match adds that topic's summary. A weak match adds only its name. The AI then decides whether to pull more.
  ```text
  You: is the battery still 40 mAh?
  (added) Topic battery: Stays 40 mAh;
          charger cable open.
  ```

- **One step pulls a topic and what is around it.** The AI gets the topic's page, the topics it links and those that link it, its newest facts, the notes with its tag, and the chats its facts came from. It goes one step out, no further. From there it opens a fact's source, and the time of that source leads to the raw data.
  ```text
  topic battery
   page        Stays 40 mAh; …
   linked      ring, charger
   facts       5 newest
   notes       3 with #battery
   chats       2 that its facts name
  ```

- **The AI follows the threads.** The `ask` skill now says, for each kind of question, what to read next. It starts from your topics and facts, and goes to raw data only to dig in. A note leads to its day, its place, the event at that time, and saved chats on the same subject. A day leads to its sleep, workouts, places and events. A stay or a trip leads to its route. The AI follows a thread only while it helps to answer, and says what it found and where.
  ```mermaid
  flowchart TD
    N["A note"] --> A["All around it"]
    A --> D["Its day"]
    A --> P["Places"]
    A --> E["Events"]
    A --> C["Chats"]
    P --> R["Route"]
  ```

- **One new read gets everything around a moment.** Give it a note, or a time. In one step it reads that note, its day's summary, the notes from 2 hours before to 2 hours after, the places, the calendar events and the health of those hours. You can ask for a wider or narrower window, up to 12 hours each way. This is faster and more sure than many small reads.
  ```text
  You: what was going on when I wrote the
       battery note?
  AI:  (reads all around the note)
       You wrote it at 14:20 at the workshop,
       20 minutes after "Ring sync" on your
       calendar. You walked 6,100 steps that
       day. 2 notes before it were about the
       charger. A saved chat on Nov 3 talks
       about the same battery.
  ```

- **The AI can read the route of a stay or a trip.** Ask *which way did I walk to the station?*, and it reads the points of that trip.
  ```text
  You: which way did I walk to the station?
  AI:  (reads the trip's 212 points)
       Up King St, then along the park,
       2.1 km in 26 minutes.
  ```

- **A project is the same project in every workspace copy.** A chat in a WongOS workspace copy is saved as *WongOS*, so you find it by its project. Turn saving off once in a project, and it stays off in every copy of it, new ones too.
  ```text
  Before: project "rural-horse"   off only here
  After:  project "WongOS"        off everywhere
  ```

- **The skill starts in more cases.** It now also starts for *what was I doing when…*, *where was I…*, *remind me what I decided about…*, questions about a trip or a stay, and any question that names one of your topics, so the AI looks in Relay Everything without being told.

## What the build needs

- **Nothing.** At the end of the build the AI connects this computer to Relay Everything and tries the new reads on your real data: it shows a sign-in link, and you click **Connect** once.

## Decision log

- **2026-11-10** — Asked how the AI should follow connected threads → chose guidance in the skill plus one new read that gets everything around a note or a moment.
- **2026-11-10** — Asked whether WongOS should move onto Relay Everything for dogfooding → chose to keep WongOS separate; it gets the plugin and its own guidance on when to use the skills.
- **2026-11-10** — Asked how to run the two parts → chose the plugin here and the WongOS install and guidance in a new workspace, "Relay Everything in WongOS".
- **2026-11-10** — Asked which apps get it in WongOS → chose Claude Code and Codex; the WongOS workspace plans that.
- **2026-11-10** — Assumed: the plugin stays in this repository, with no separate plugin repository, because Claude Code and Codex both install it from the `plugin/` folder through the root marketplace file today, and Codex can fetch that folder alone.
- **2026-11-10** — Assumed: the read around a moment does not search saved chats itself, because chat search needs words, and the AI picks better words from the note than code does; the skill tells the AI to search chats with the note's key words.
- **2026-11-10** — Assumed: the window is 2 hours each way by default, and at most 12, because 2 hours holds the notes and events that belong to one moment, and 12 covers a half day without a full day's reads.
- **2026-11-10** — Asked whether WongOS chats save to Relay Everything → chose to save WongOS chats, and to keep all Claymoo data out of Relay Everything.
- **2026-11-10** — Assumed: a project is its main git repository, so saving and the project's name follow it into each workspace copy, because the WongOS workspace found that saving off resets in each new copy, and that breaks the only-WongOS choice.
- **2026-11-10** — Assumed: photos stay out, because the web API that the plugin reads has no photo list; only the AI connector reads photos.

- **2026-11-10** — Asked how to plan chat processing and a better way to read → chose three plans in order: (1) each person's knowledge web in Cloudflare Artifacts, (2) your own Claude builds it in the background, (3) the AI reads the web first and looks by itself; this plan becomes part 3.
- **2026-11-10** — Asked where chat digests are made → chose your own Claude, with helper agents, as WongOS's background run does, not a model on the server.
- **2026-11-10** — Asked whether the knowledge web shows in the app → chose later; for now only AIs read and write it.
- **2026-11-10** — Asked how the AI should see the threads it can pull → chose, for the redraw: a hook at chat start shows the top-level topics from the web's `README.md`, one line each; a hook on each message matches its words against the topic names in the computer's copy, with no network call, and adds a topic's summary on a clear match and only its name on a weak one; a `topic <name>` pull gets the page, its linked topics, and the newest facts, notes and chats with its tag in one step, one step out and no further.
- **2026-11-10** — Asked whether health and places get topics → chose no; everything connects by time, so the read around a moment also gets the health of those hours.
- **2026-11-10** — Asked to build and publish this plan after part 1 → chose to build it now on part 1, before part 2; the plan is redrawn here to start from the web, as the earlier choices say.
- **2026-11-10** — Assumed: the chat-start hook prints from the computer's copy and starts the sync on its own, because a hook has 10 seconds and a sync may take longer; a new copy shows its topics from the next chat.
- **2026-11-10** — Assumed: a clear match is a topic's whole name, or its last part such as `charging` for `ring/charging`, as a word in the message; a weak match is a word that starts a topic's name; at most 3 topics are added, because more would crowd the message.
- **2026-11-10** — Assumed: a project's topic is the topic with the project's name, such as `wongos`, because topics are named by tags and a project has no other link to the web.
- **2026-11-10** — Assumed: the topic pull reads the page and its links from the copy and makes three reads of the web API, facts, notes and the chats its facts name (at most 3), because more chats would be the raw data the AI should not start from.
- **2026-11-10** — Assumed: Codex gets the same hooks where it runs them; where it does not, the skill still tells the AI to look at the topics first.

## Capabilities

### New Capabilities

### Modified Capabilities
- `relay-agent-plugin`: the AI sees the person's topics when a chat starts and the topics a message names, pulls a topic in one step, reads stay and trip routes, reads all around a moment in one step with its health, and follows connected threads from topics down; a project is its main repository in every workspace copy, for its name and for saving off.

## Impact

- `plugin/bin/relay.mjs`: `points`, `around` and `topic` commands.
- `plugin/bin/hook.mjs`, `plugin/hooks/hooks.json`: the topic list at session start and the topic match on each message (`UserPromptSubmit`).
- `plugin/lib/topics.mjs`: reads the copy's topics, summaries and links, and matches words.
- `plugin/lib/transcript.mjs` `projectRoot`: a git worktree resolves to its main repository; old `off.json` entries keep working.
- `plugin/skills/ask/SKILL.md`: the threads guide and wider triggers.
- `plugin/test/relay.test.mjs`, `plugin/test/skills.test.mjs`: tests for the new commands and the skill text.
- `plugin/README.md`, `plugin/.claude-plugin/plugin.json` (version 0.4.0), `site/src/content/docs/connections/claude-code.md`, `wiki/stack/relay-chats.md`.
- No server change: every read uses a web API route that exists.
