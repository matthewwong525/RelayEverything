# The rules of this knowledge web

Your AI reads this page before it writes a fact or a page. Change it, and your AI follows your rules. Relay Everything checks only the memory's columns, a fact's tags and its sources.

## Facts

- A fact is one row in your memory. Each fact has one short sentence in `text`, and one kind in `kind`:
  - `user`: who you are, what you know, and how you like to work.
  - `feedback`: how you want a job done: a correction, or a way that worked, with its reason.
  - `project`: a fact, a decision or a plan about something that goes on.
  - `reference`: where to find a thing: a link, a file or a place to look.
  - `thread`: a question or a job that is still open.

  A fact saved with an older kind keeps its word, and reads as its new kind: `open` as `thread`, `preference` as `feedback`, and `fact`, `decision` and `plan` as `project`.
- Read the memory's columns with `relay.mjs columns`, and fill each column that fits.
- Tags name topics, such as `battery` or `bike-charger`. A fact has at least one tag, and a tag for each topic it touches.
- A fact has at least one source: a link to the record it came from.
- When a fact changes, add a new fact that replaces the old one. Never add the same fact two times.
- Add facts with `relay.mjs add-facts`.

A sample fact:

```json
{ "tags": ["bike-battery"], "sources": ["relay:chat/7f3a#120"], "replaces": ["fk2pq"],
  "fields": { "kind": "project", "text": "The bike's battery is 500 Wh, not 400 Wh." } }
```

## Pages

- Each page is a topic, in `topics/`. The first fact with a tag makes its page. Make no page before that.
- One subject, one page. Pages sit side by side in `topics/`, with no folders: your web is a graph of linked pages, not a tree.
- Names are lowercase words with hyphens, the same as the tag: the tag `bike-battery` is `topics/bike-battery.md`. A folder or a name with `/` that your web already has stays as it is.
- A topic that grows big splits into smaller pages beside it, such as `bike-battery` and `bike-charger`. The first page keeps a short summary and links each smaller page. It never becomes a folder.
- Each page starts with `title`, `summary` (one line) and `updated` in its frontmatter.
- `README.md` lists each topic with its summary.
- A page sums up the live facts with its tag, in plain sentences. It lists no fact ids.
- A page links the topics it connects to, with a few words that say how: topics that share a fact, a note or a chat. It also links a topic wherever it names it. A chat gets no page: its facts link to it.

A sample page, `topics/bike-battery.md`:

```markdown
---
title: Bike battery
summary: The bike's battery size and how it charges.
updated: 2026-11-10
---
# Bike battery

The battery is 500 Wh: 400 Wh did not last a long ride. It charges on the [charging dock](bike-charger.md).
```

## Look

To answer a question: read `README.md`, read the topic's page, run `relay.mjs facts --tag <topic>` and `relay.mjs notes --tag <topic>`, then open a source.

## Links

- A link to a record is `relay:<kind>/<id>`. The kind is `note`, `chat`, `day`, `night`, `workout`, `stay`, `event` or `photo`. A chat link can name a message: `relay:chat/<id>#<number>`.
- Never copy a health value or a place's coordinates into a fact or a page. Link its day, night, workout or stay.
- Write each link one way only. A fact links its sources; a page links pages and records. Find a page's facts by its tag, and a record's facts with `relay.mjs facts --source <link>`.

## The builder's record

`.relay/` is not a topic. It holds the daily build's record: `read.log` lists each chat and note it read, and `builds.log` each day's build. Only the build writes there.
