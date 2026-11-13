---
name: relay-ask
description: Read the person's Relay Everything (topics, facts, notes, health, sleep, workouts, places and routes, calendar and saved AI chats), add a note, or keep an agent's own tables in their agents' database. Use for /relay-ask, or when the person asks about their notes, their day, how they slept, their steps or workouts, where they went, a trip or a stay, their calendar, or a saved chat; asks what was I doing when…, where was I…, what did I decide about…, or remind me what I decided about…; names one of their Relay Everything topics; or asks to note something in Relay Everything.
allowed-tools: Bash(node:*)
---

# Ask Relay Everything

Each command runs Relay Everything's copy in this project, `.agents/relay/`. When that folder is missing, this is the Relay Everything plugin: in each command, put the folder two levels above this file in place of `$(git rev-parse --show-toplevel)/.agents/relay`. Never install the copy unless the person asks: `/relay:move` moves it into this project.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it. In Codex's sandbox, the command can not reach the network or write this computer's Relay Everything folder.

Each command prints JSON:

```bash
node "$(git rev-parse --show-toplevel)/.agents/relay/bin/relay.mjs" <command> [value] [--field value ...]
```

## Start from your topics

1. A chat starts with the person's topics, one line each, from this computer's copy of their knowledge web. A message that names a topic gets a line with that topic's summary. Use these first.
2. `topic <name>` pulls a topic in one step: its page, the topics it links and those that link it, its newest facts, its notes, and the chats its facts came from. With memory on, it prints memory's pull as text, with the notes and chats at the end.
3. A fact's `sources` lead on: `relay:note/<id>` → `note <id>`, `relay:chat/<id>` → `chat <id>`, `relay:day/<day>` → `day <day>`.
4. Read raw data only to dig in, by the time of a source.

## Follow the threads

| From | Read next |
| --- | --- |
| A topic | `topic <name>`, then a fact's source |
| A fact | its source; `fact <id>` for what it replaced |
| A note | `around <id>` and `chats --q` with the note's key words: always both |
| A day | `day <day>`, then `nights`, `workouts`, `places`, `calendar` |
| A stay or a trip | `points <id>` for its route |
| A saved chat | the notes and days it names, by their time |

For a question about a note, read both before you answer: a chat can hold the why. Follow a thread only while it helps to answer. Read at most one more step without a reason, and stop when the question is answered. Say where each fact came from: the note, the day, the place, the event or the chat.

## Commands

- `topic <name>` pulls a topic, as above.
- `around <note id>` reads all around a note: the note, its day, and the notes, places, calendar events and hourly steps and heart rate from 2 hours before to 2 hours after. `around --at <time>` does the same for a time. `--hours <n>` sets the window, 1 to 12 each way. A part that failed is under `errors`.
- `notes --q "words"` finds notes; `notes --from <time> --to <time>` reads a time range; `notes --tag <topic>` finds the notes on a topic. `note <id>` reads one.
- `day <YYYY-MM-DD>` sums up one day: notes, health, sleep, workouts, places and events.
- `health <type> --from <time> --to <time> [--per hour|day]`. Types: steps, heart_rate, sleep, workout, weight, resting_heart_rate, hrv_sdnn, hrv_rmssd, blood_oxygen, blood_pressure_systolic, blood_pressure_diastolic, cycle_flow, mindful, water.
- `nights`, `workouts`, `places`, `calendar [--q "words"]`: each with `--from <time> --to <time>`. Add `--stages` to `nights` for each night's stage timeline.
- `points <id>` reads the route of a stay or a trip, by its id from `places` or `day`; `points --from <time> --to <time>` reads by time, at most 7 days.
- `chats --q "words"` finds saved AI chats; `chat <id>` reads one.
- `facts --q "words"` searches the memory of facts; `--tag <topic>` finds a topic and its parts, `--source relay:chat/<id>` the facts from one record, and `--<column> <value>`, such as `--kind project`, one column's value. Add `--all` for replaced facts too. `fact <id>` reads one, with what it replaced.
- `columns` lists the memory's columns.
- `me` says which device this is.
- `add-note` adds a note with the text from stdin, only when the person asks: `node … add-note <<'NOTE'` … `NOTE`.
- `add-facts` adds facts from a JSON list on stdin, each with `tags`, `sources` and `fields`, and `replaces` for the facts it replaces. `change-columns` changes the columns from JSON on stdin. `tag fact|note <id> --add <topics> --remove <topics>` changes topics, as a comma list. Read the knowledge web's `FORMAT.md` first, and do these only when the person asks.
- `db "<sql>" [--params '<JSON list>']` runs a SQLite command in the person's agents' database: a database only for the agents on their computers, where you may make any table, such as `CREATE TABLE reading_list (title TEXT)`. `db --file <path>` runs a file's commands, each ending with `;`, all or none. `db tables` lists the tables other agents made, with their columns and row counts: look there before you make a new one. Relay Everything's notes, health, places, chats and facts are not in it. Never copy health or place data into it.
- `node "$(git rev-parse --show-toplevel)/.agents/relay/bin/knowledge.mjs" sync` gets this computer's copy of the knowledge web, and sends its changes; `status` says where it is.

Read more with `--limit <n>` and `--cursor <nextCursor>` from the last answer.

**Time zone.** A `<time>` is a day (`2026-11-04`), a time with no offset (`2026-11-04T09:00`), or a time with its offset. A day or a time with no offset is in this computer's time zone, and so are the times in each answer. If the person names another zone, add `--timezone <IANA name>`, such as `--timezone Europe/London`. `--to` is the first moment *not* included: yesterday is `--from <yesterday> --to <today>`.

If a command prints a line instead of JSON, show the person that line.
