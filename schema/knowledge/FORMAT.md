# The rules of this knowledge web

Your AI reads this page before it writes a fact or a page. Change it, and your AI follows your rules. Relay Everything checks only the memory's columns, a fact's tags and its sources.

## Facts

- A fact is one row in your memory. Each fact has one short sentence in `text`, and one kind in `kind`: `fact`, `decision`, `preference`, `plan`, `open` or `reference`.
- Read the memory's columns with `relay.mjs columns`, and fill each column that fits.
- Tags name topics, such as `battery` or `bike/charging`. A fact has at least one tag.
- A fact has at least one source: a link to the record it came from.
- When a fact changes, add a new fact that replaces the old one. Never add the same fact two times.
- Add facts with `relay.mjs add-facts`.

A sample fact:

```json
{ "tags": ["bike/battery"], "sources": ["relay:chat/7f3a#120"], "replaces": ["fk2pq"],
  "fields": { "kind": "decision", "text": "The bike's battery is 500 Wh, not 400 Wh." } }
```

## Pages

- Each page is a topic, in `topics/`. The first fact with a tag makes its page. Make no page before that.
- One subject, one page. A topic that grows big becomes a folder, with a `README.md` that links its parts.
- Names are lowercase words with hyphens, the same as the tag: the tag `bike/battery` is `topics/bike/battery.md`.
- Each page starts with `title`, `summary` (one line) and `updated` in its frontmatter.
- `README.md` lists each top-level topic with its summary.
- A page sums up the live facts with its tag, in plain sentences. It lists no fact ids.
- A page links other pages by their path. A chat gets no page: its facts link to it.

A sample page, `topics/bike/battery.md`:

```markdown
---
title: Bike battery
summary: The bike's battery size and how it charges.
updated: 2026-11-10
---
# Bike battery

The battery is 500 Wh: 400 Wh did not last a long ride. It charges on the [charging dock](charging.md).
```

## Look

To answer a question: read `README.md`, read the topic's page, run `relay.mjs facts --tag <topic>` and `relay.mjs notes --tag <topic>`, then open a source.

## Links

- A link to a record is `relay:<kind>/<id>`. The kind is `note`, `chat`, `day`, `night`, `workout`, `stay`, `event` or `photo`. A chat link can name a message: `relay:chat/<id>#<number>`.
- Never copy a health value or a place's coordinates into a fact or a page. Link its day, night, workout or stay.
- Write each link one way only. A fact links its sources; a page links pages and records. Find a page's facts by its tag, and a record's facts with `relay.mjs facts --source <link>`.
