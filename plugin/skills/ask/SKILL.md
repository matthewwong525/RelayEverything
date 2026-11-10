---
name: ask
description: Read the person's Relay Everything (notes, health, sleep, workouts, places, calendar and saved AI chats), or add a note. Use when the person asks about their notes, their day, how they slept, their steps or workouts, where they went, their calendar, or a saved chat, or asks to note something in Relay Everything.
allowed-tools: Bash(node:*)
---

# Ask Relay Everything

`${CLAUDE_PLUGIN_ROOT}` is the plugin's folder. In Codex it is empty: use the folder two levels above this file.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it. In Codex's sandbox, the command can not reach the network or write this computer's Relay Everything folder.

Each command prints JSON:

```bash
node "${CLAUDE_PLUGIN_ROOT}/bin/relay.mjs" <command> [value] [--field value ...]
```

- `notes --q "words"` finds notes; `notes --from <time> --to <time>` reads a time range. `note <id>` reads one.
- `day <YYYY-MM-DD>` sums up one day: notes, health, sleep, workouts, places and events.
- `health <type> --from <time> --to <time> [--per hour|day]`. Types: steps, heart_rate, sleep, workout, weight, resting_heart_rate, hrv_sdnn, hrv_rmssd, blood_oxygen, blood_pressure_systolic, blood_pressure_diastolic, cycle_flow, mindful, water.
- `nights`, `workouts`, `places`, `calendar [--q "words"]`: each with `--from <time> --to <time>`. Add `--stages` to `nights` for each night's stage timeline.
- `chats --q "words"` finds saved AI chats; `chat <id>` reads one.
- `facts --q "words"` searches the memory of facts; `--tag <topic>` finds a topic and its parts, `--source relay:chat/<id>` the facts from one record, and `--<column> <value>`, such as `--kind decision`, one column's value. Add `--all` for replaced facts too. `fact <id>` reads one, with what it replaced.
- `notes --tag <topic>` finds the notes on a topic.
- `columns` lists the memory's columns.
- `me` says which device this is.
- `add-note` adds a note with the text from stdin, only when the person asks: `node … add-note <<'NOTE'` … `NOTE`.
- `add-facts` adds facts from a JSON list on stdin, each with `tags`, `sources` and `fields`, and `replaces` for the facts it replaces. `change-columns` changes the columns from JSON on stdin. `tag fact|note <id> --add <topics> --remove <topics>` changes topics, as a comma list. Read the knowledge web's `FORMAT.md` first, and do these only when the person asks.
- `node "${CLAUDE_PLUGIN_ROOT}/bin/knowledge.mjs" sync` gets this computer's copy of the knowledge web, and sends its changes; `status` says where it is.

Read more with `--limit <n>` and `--cursor <nextCursor>` from the last answer.

**Time zone.** A `<time>` is a day (`2026-11-04`), a time with no offset (`2026-11-04T09:00`), or a time with its offset. A day or a time with no offset is in this computer's time zone, and so are the times in each answer. If the person names another zone, add `--timezone <IANA name>`, such as `--timezone Europe/London`. `--to` is the first moment *not* included: yesterday is `--from <yesterday> --to <today>`.

If a command prints a line instead of JSON, show the person that line.
