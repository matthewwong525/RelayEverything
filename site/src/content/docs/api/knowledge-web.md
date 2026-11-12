---
title: Memory and knowledge web
description: Your memory of facts and your knowledge web of topic pages in Relay Everything, how a connected computer reads and writes them, and the default rules for both.
---

Relay Everything keeps two things that your own AI writes from your chats and notes:

- **Your memory**: a table of short facts in your own space, such as *the bike's battery is 500 Wh*. Each fact has topics, called tags, and links to the chat or note it came from. A fact is only added, never changed: a new fact replaces an old one, and the old one stays readable, marked replaced.
- **Your knowledge web**: one page for each topic, in a git repository that only your computers can reach. A page sums up the live facts on its topic.

A computer connected with the [Relay Everything plugin](../../connections/claude-code/) writes both: once a day, [your own AI builds them](../../connections/claude-code/#your-web-builds-itself) from your chats and notes. Your [AI connector](../../connections/connect-your-ai/) and your API keys read the memory. A phone's key reaches neither.

## Your memory's columns

Each fact has the columns Relay Everything keeps: its id, tags, sources, the facts it replaces, the device that added it, and the time. Every other column is yours. A new memory has two: `kind` and `text`, both needed on each new fact.

A connected computer can add a column, change a column's note or whether it is needed, and remove a column. A column has one type, which never changes: `text` (up to 400 characters), `number`, `date`, `yes_no`, or `words` (a list of up to 20 short words). The memory has at most 20 columns. A removed column's values stay in the old facts. Relay Everything keeps each change, with its device and time. Each new fact is checked against the columns: a value of the wrong type is refused, and nothing is stored.

## Topics on notes

A computer can also add topics to a note, and remove them. The note's words stay as you wrote them. A topic finds itself and its parts: `bike` finds `bike/charging`. When you delete a note, its topics go with it.

## For people who build their own plugin

Any plugin with a computer's key reaches the memory and the web in the same way. The plugin gets its key from the same sign-in link as the Relay Everything plugin: [The computer's sign-in](../../connections/claude-code/#the-computers-sign-in).

1. **Open the web.** `POST /v1/knowledge/access` answers `{ "remote": "…", "token": "…", "expiresAt": "…" }`: your web's git address, and a pass that reads and writes it for one hour. Give the pass to git as a header, never in the address or a file: `git -c http.extraHeader="Authorization: Bearer $TOKEN" clone "$REMOTE"`. A server whose Cloudflare account has no Artifacts answers `501`, `not_set_up`.
2. **Read the rules.** Read your web's own `FORMAT.md`, and follow it over the default below. Read the columns with `GET /v1/memory/columns`.
3. **Add facts.** `POST /v1/memory` with `{ "facts": [ … ] }`, up to 50 at a time. Give each fact your own `clientId`, so a resend after a lost answer is kept once. All of the facts are added, or none.
4. **Find facts.** `GET /v1/memory?tag=battery`, `?q=words`, `?source=relay:chat/<id>`, or any column as its own field, such as `?kind=project`. `?kind=project` also finds the facts saved with an older kind that reads as `project`, such as `decision`; each fact shows the kind word it was saved with. Add `all=true` for replaced facts too.
5. **Change topics.** `POST /v1/memory/{id}/tags` and `POST /v1/notes/{id}/tags` with `{ "add": ["bike/charging"], "remove": ["bike"] }`. A fact keeps at least one topic.
6. **List your chats.** `GET /v1/chats?from=2026-11-03&to=2026-11-10` with no `q` lists every saved chat active in that time, newest first, each with its message count and last time. Read one from a message on with `GET /v1/chats/{id}?cursor=<seq>`. The daily build keeps what it read in [the builder's record](#the-builders-record).

Only a computer's key changes the memory and opens the web: an API key and the AI connector read the memory, and change nothing in it. The [Web API reference](../v1-reference/) lists each route's fields.

### The memory store

The plugin's memory, from WongStack, reaches your memory through its own store routes: `POST /v1/memory/v2/<request>`, such as `facts`, `write`, `digest` or `transcript`, with a computer's key. Give memory the address `<your-relay-server>/v1/memory`. Each fact there has a number, such as `#12`, beside its `f…` id. The store keeps memory's chat transcripts in your space's sealed files, and when it kept none, it gives the saved chat as text. A chat that memory read shows `memory: true` in `GET /v1/chats`, and the daily build skips it. Memory read a chat when it captured the chat, or a fact came from it; a chat that memory has not captured yet shows `memory: false`. An API key, a phone's key and the AI connector get `403` from these routes.

### Move a WongStack memory in

`node scripts/import-wongstack-memory.mjs --from <WongStack checkout>` moves a WongStack project's memory into your space, one time, with this computer's key. Add `--dry-run` to count the facts and send nothing. Each fact keeps its number, date, author, kind, topics and sources, and a replaced fact stays linked to its replacer. Run it again to bring only the facts added since; a fact whose number is taken gets the next free number, and the script prints it. The script only reads the old memory. It sends to `POST /v1/memory/import` and `POST /v1/memory/import/transcript`.

## The default rules

Each new web starts with this `FORMAT.md`. You can change your copy, and your AI follows your copy.

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
