# Your memory and knowledge web: one memory table and topic pages in your Relay Everything, which any AI plugin can read, write and shape with the computer's key

**Status:** in-progress
**Branch:** fix-plugin-wongos-install
**Open questions:** none

## Why

Relay Everything holds the raw data: every note, chat message, place and health value. An AI that starts from raw data reads too much and misses how things connect. Places already have a layer on top: points become stays and trips. Chats, notes and everything else need the same kind of layer: pages about whatever you talk about, each fact linked back to the record it came from. This plan makes the places where that layer lives: one memory table of facts in the database, and topic pages in a web of linked pages. Any plugin, yours or someone else's, builds on the same two. The next plan has your own Claude fill it.

## What Changes

- **Each person gets a knowledge web.** It is a folder of plain pages, kept in Relay Everything as a git repository, in Cloudflare Artifacts. Every change is kept, so nothing is lost and two computers can both write. Relay Everything makes it the first time a computer asks for it, with a start page and the format page in it.
  ```text
  README.md          start here: links to every section
  FORMAT.md          your rules: fact types, pages, links
  topics/battery.md  made when the first
  topics/sam.md      fact names it
  ```

- **Every fact links back to its source, and a page finds its facts by its topic.** A fact says *decided the battery stays 40 mAh*, and links to the exact chat message, note, day, stay or event. A topic page sums up its facts in plain sentences, with no fact ids. Its name is its tag: to dig in, the AI searches your memory for `#battery`, then opens a fact's source. `FORMAT.md` writes down this way to look.
  ```text
  1. Read     topics/battery.md
  2. Search   memory for #battery
  3. Open     relay:chat/7f3a#120
  ```

- **Three levels, from topics down to raw data.** The AI starts small and pulls a thread only when it helps. It sees the top-level topics, each with one line. It picks a topic and gets the page, the topics it links, and the newest facts, notes and chats with its tag. It opens a fact's source, and from there the raw data of that time. This plan makes the places each level reads from. Part 2 has your own Claude fill them. Part 3 shows the topics when a chat starts, adds a topic's summary when your words name it, and pulls a topic in one step.
  ```text
  0  Topics      battery · ring · sam
       ▼ the AI picks one
  1  A topic     page, linked topics,
                 facts, notes, chats
       ▼ dig in
  2  A source    chat message, note
       ▼ by its time
  3  Raw data    place, health, events
  ```

- **Health and location values stay in their own place.** A page never copies a heart rate, a sleep time or a map point. It links to the day, the night or the stay instead. Those values stay only where they live today, and get no topics. They connect by time instead: a note, a fact or a chat leads to the place, the health and the events of its hours. Part 3 adds that read.

- **A connected computer can read and add facts, and read and write its person's web.** Claude Code and Codex get a short-lived pass from the computer's key: no new key, nothing to paste. This computer keeps a copy of the web in the plugin's folder and sends its changes back. It syncs when a chat starts and after a build, and at most once every 15 minutes, so the web stays cheap to run for many people. A phone key can't open the web or read facts. When you *Turn off* a computer, it can't open the web again; a pass it already got works for at most one more hour.
  ```mermaid
  sequenceDiagram
    participant C as Your computer
    participant R as Relay Everything
    participant W as Your knowledge web
    C->>R: Pass, please (computer key)
    R-->>C: A pass for one hour
    C->>W: Get the pages
    C->>W: Send changes
  ```

- **You set the rules.** `FORMAT.md` in your web says which kinds of fact there are, how a fact and a page are written, and how links look. The first copy is a default; you can change it, or ask your AI to. The columns of your memory table are yours to change too (below). Every plugin reads your web's own `FORMAT.md` before it writes, so your rules hold for your AI and for anyone else's plugin. The website shows the default.
  ```text
  Database
   Raw data     chats, notes, days, stays…
     ▲ linked from
   Facts        [decision] f7k2 Nov 3
                Battery stays 40 mAh.
                #battery relay:chat/7f3a#120
     ▲ summed up by
  Web
   Pages        topics/battery.md
   FORMAT.md    your rules
  ```

- **Only topics, grown from use.** There are no set folders for people, projects or places. A topic page is made when the first fact names it, and it can be about anything: a person, a project, a place or an idea. When a topic grows big, it becomes a folder with its own start page and smaller pages under it. Each page has a one-line summary, and `README.md` lists the top-level topics with theirs. A chat gets no page of its own: its title and summary stay beside the chat in Relay Everything, as they do today, and its facts link to it.
  ```text
  topics/battery.md
  topics/sam.md
  topics/ring/README.md     grew into
  topics/ring/charging.md   a folder
  ```

- **Your memory is one table in your Relay Everything.** Each row is a fact, beside your notes and chats. Relay Everything keeps some columns the same on every row: the id, the tags such as `#battery`, the source links, what the fact replaces, the device and the time. A tag names the topic that sums it up: `#battery` is `topics/battery.md`. The other columns are yours: a new memory has `kind` and `text`, and you or any plugin can add, change or remove columns. A fact's words can only be added, never changed: a newer fact replaces it, and both stay, so you can see what you thought before. Its tags can change, so your Claude can move facts into a better topic and keep topics clean. Every AI can search your memory, the Claude app on your phone and ChatGPT too, through the AI connector.
  ```text
  Kept by Relay Everything   Yours to change
  id        f7k2             kind  decision
  tags      #battery         text  Battery stays
  sources   relay:chat/7f3a        40 mAh.
  replaces  -                + any column you add
  device, time
  ```

- **Notes get topics too, from your own Claude.** You never pick a topic. Your Claude reads your notes on your computer and gives each one its topics, as it does for chats. When it makes a new topic, it looks back at older facts and notes, and moves the ones that fit. A topic then shows your notes beside its facts. Your words in a note stay as you wrote them; only its topics change.
  ```text
  Note  "Ring charger cable is too short"
        topics  #ring/charging   ← your Claude
  ```

- **Any plugin can build on your memory and your web, and on nothing else.** A person who makes their own plugin connects it the same way: a sign-in link gives the computer its own key. With that key, the plugin reads and adds facts, changes the memory table's columns, and reads and writes your web. It can't make a second table, send its own database commands, or change your notes, chats, health or places. Relay Everything keeps each column change with the device that made it, so you can see which plugin added what.
  ```text
  Plugin ──key──▶ /v1/memory            facts
                  /v1/memory/columns    its columns
                  /v1/knowledge/access  the web
            ✗ any other table
  ```

- **Only two kinds of link are written; the rest is found.** A fact links to its sources. A page links to other pages, such as `topics/ring/` to `topics/battery.md`. A page's facts are found by its tag, and a chat's facts by a search for the chat. Nothing is written twice: a page that listed fact ids would point at old facts each time a fact is replaced.
  ```text
  chat 7f3a ◀── fact f7k2   #battery
                              ▲ found by tag
                topics/battery.md
  ```

- **Deleting your account deletes your memory and your web.** *Delete my account* now also deletes your memory table and your knowledge web. It can't be undone.

- **A server you run yourself** gets the web only when its Cloudflare account has the Workers Paid plan, which Artifacts needs. Without it, your memory still works, the plugin says the web is not set up on that server, and everything else works.

## What the build needs

- **Cloudflare Artifacts**: Ready. Relay Everything's Cloudflare account has Artifacts on the Workers Paid plan, and `CLOUDFLARE_API_TOKEN` in `.env` lists its namespaces. Cloudflare starts to bill Artifacts on 2026-11-12: storage over 1 GB a month and over 10,000 operations a month, both small.

## Decision log

- **2026-11-10** — Asked how to plan chat processing and better reads → chose three plans in order; this is part 1, each person's knowledge web and access to it.
- **2026-11-10** — Asked where the web lives → chose Cloudflare Artifacts inside Relay Everything, as a web of linked pages that any plugin can store to and read from by an open format.
- **2026-11-10** — Asked whether the web shows in the app → chose later; for now only AIs read and write it.
- **2026-11-10** — Assumed: each person's web is one repository, named by their person id, in its own namespace for live and for staging, because a repository's pass covers just that repository, so one person's pass can't reach another's.
- **2026-11-10** — Assumed: a new web is a copy of one start repository holding `README.md` and `FORMAT.md`, because Artifacts can't make a repository with files in it, but can copy one.
- **2026-11-10** — Assumed: a pass lasts one hour, because *Turn off* can't call back a pass already given, and one hour keeps that window short while a long sync still finishes.
- **2026-11-10** — Assumed: health and location values are never copied into pages, only linked, because AGENTS.md keeps them only in `relay_health` and `relay_locations`.
- **2026-11-10** — Assumed: the computer's copy and its send-back come in this plan, as `knowledge.mjs` in the plugin, because it is how a computer opens the web; the building of pages waits for part 2, and reading pages first waits for part 3.
- **2026-11-10** — Asked whether to keep syncs rare to hold the cost down → chose yes: a computer syncs when a chat starts and after a build, and at most once every 15 minutes; the AI reads the computer's own copy between syncs.
- **2026-11-10** — Asked (the person's own words) for the web to define how facts are written, like the memory store → chose: the web holds its own editable `FORMAT.md` that every plugin follows, and a facts layer of short, typed, dated lines that are replaced and never changed, under the pages.
- **2026-11-10** — Assumed: the default fact kinds are WongStack's that fit a life, `fact` (something true, such as who Sam is), `decision`, `preference`, `plan`, `open` (a question still open) and `reference`, because the person knows them from WongOS and can change them in `FORMAT.md`.
- **2026-11-10** — Assumed: the rules are kept by the AI that reads them, not by code on the server, because the person can change them, and a server check would hold the old rules; the server checks only the memory table's own columns: each value's type, the required columns, a tag and a source.
- **2026-11-10** — Asked whether facts, pages and chats link both ways, and what WongStack has that this lacks → chose: links are written one way (fact → source, page → facts, chat page → its facts) and the way back is found by search; fact lines carry subject tags that name their page. The rest of WongStack's memory goes to later parts: part 2 gets the write gate, a ledger of how far each chat was read, and, at the first chat of each day, one helper that tidies the web and one that reads older chats into facts, with no separate dream run; part 3 gets a short digest at chat start, recall over facts and pages, backlinks, and a project's facts when a chat starts in it.
- **2026-11-10** — Asked (review note) whether a page needs a link to each fact, or can find its facts by its topic → chose: a page names no fact ids; its facts are found by a memory search for its tag, and `FORMAT.md` writes down that way to look; a page links only other pages, and a fact links its sources. This replaces *page → facts* in the earlier choice on links, because a listed fact id goes stale when the fact is replaced.
- **2026-11-10** — Asked how the AI should see the threads it can pull, with notes, health and places in it → chose three levels: top-level topics, then one topic with what is around it, then a source, then raw data by its time; this plan makes the places, part 2 fills them, part 3 adds the hooks and the one-step topic pull.
- **2026-11-10** — Asked how much the hook adds when your words name a topic → chose the topic's summary on a clear match and only its name on a weak one; part 3 builds it.
- **2026-11-10** — Asked how notes get topics → chose only your own Claude, with no topic typed by you; the person said a person should never think about where a note goes.
- **2026-11-10** — Asked where the topic list and topic pull run → chose all AI work on the computer by your own Claude's helpers, with no AI on the server, because a model on the server costs too much and is not as good; the topic pull reads the computer's copy of the web and the normal web API, so it needs no new server route.
- **2026-11-10** — Asked whether health and places get topics → chose no; everything connects by time, so a note leads to the place, health and events of its hours; part 3's read around a moment adds the health of those hours.
- **2026-11-10** — Assumed: the tags of a fact and of a note can change, and their words, sources and columns can't, because your Claude must move things into a new topic to keep topics clean, and a tag is where a thing is filed, not what it says. Each tag change is kept with its device and time.
- **2026-11-10** — Assumed: each page has a one-line `summary`, and `README.md` lists the top-level topics with theirs, because the chat-start hook shows that list as level 0 and must stay short.
- **2026-11-10** — Asked to leave the key check on the web out → chose no key check in this plan; the plugin already hides keys in the chats it sends.
- **2026-11-10** — Asked whether the web needs people, projects and places → chose only topics, grown from use: a topic page is made by the first fact that names it, a big topic becomes a folder, and there is no `person` kind; `fact` covers who someone is.
- **2026-11-10** — Assumed: a chat gets no page in the web, because Relay Everything already keeps a title and summary beside each chat, and a second summary would go stale; the chat's facts link to it, and a search finds them.
- **2026-11-10** — Asked where facts live → chose the database, in each person's space beside notes and chats, so every AI and the server can search them and the server keeps them add-only; topic pages and `FORMAT.md` stay in the web.
- **2026-11-10** — Assumed: the AI connector gets a memory search in this plan, because search from the phone's AI is why facts moved to the database; the plugin reads them with `relay.mjs facts`, and its copy for the auto-look waits for part 3.
- **2026-11-10** — Asked (the person's own words) to let people who build their own plugin use the database and Artifacts, limited to one table, such as `memory`, whose definition they can change → chose: the facts table becomes the person's one `memory` table; a computer key reads and adds facts and changes its columns through the web API, and reaches no other table; any plugin opens the web with the same pass.
- **2026-11-10** — Assumed: one memory table for each person, shared by every plugin, not one for each plugin, because the person asked for one table, and plugins then share what they learn.
- **2026-11-10** — Assumed: a caller never sends a database command; the server keeps the person's columns as checked values on each row, because a caller's own command could reach other tables, and a fixed table needs no migration when a column changes.
- **2026-11-10** — Assumed: Relay Everything keeps the id, tags, sources, replaces, device and time on every row, and a new memory starts with `kind` and `text`, because topic pages need the tags and every fact needs its source.
- **2026-11-10** — Assumed: facts stay add-only, with replace, for every plugin, because a plugin that changes a fact could erase what the person thought before.
- **2026-11-10** — Assumed: a column can be added, its note or *required* changed, or removed, but its type can't change, and a removed column's values stay in old rows, because an old fact must still read the same.
- **2026-11-10** — Assumed: links use `relay:<kind>/<id>`, such as `relay:chat/<id>#<message>` and `relay:day/2026-11-04`, because a link that names no server works on any server, and the web API reads each kind by that id.
- **2026-11-10** — Assumed: the pass route sits on the connector's `/v1/`, beside the other web API routes, and both the connector and the shared server bind `KNOWLEDGE`, because the web API lives on the connector and the account delete runs on the server.
- **2026-11-10** — Assumed: wrangler stays at 4.144.0, because that version already deploys the company app's `artifacts` binding and its types hold `Artifacts`.
- **2026-11-10** — Assumed: a server with no binding, or no `start` repo, answers `501 not_set_up`, and a fork still running after a few tries answers `503 try_again`.
- **2026-11-10** — Assumed: the connector has seventeen tools, not sixteen, because `memory` and `read_fact` join the fifteen.
- **2026-11-10** — Assumed: no session-start hook syncs the web in this plan; `knowledge.mjs sync` runs when asked, and part 3 adds the hook.
- **2026-11-10** — Assumed: a note's answer does not list its topics yet; a tag change answers the topics, and `tag=` finds them.
- **2026-11-10** — Assumed: the columns' change list is asked for with `changes=true`, as the web API reads every other yes or no.
- **2026-11-10** — Assumed: the made-up facts go in `app/tests/relay-space-rows.sql`, the space's sample data, as a space has no D1 seed in `schema/seed.sql`.
- **2026-11-10** — Assumed: an API key and a connected app get `403` with one message on every route that changes the memory or opens the web, because only a computer's key may.
- **2026-11-10** — Assumed: a page both computers changed keeps both versions by git's line join (`merge=union`), set only in the copy's own `.git/info/attributes`, and a file that can't join keeps this copy's version with the web's beside it as `<name>.other`.
- **2026-11-10** — Assumed: the examples say `bike`, not `ring`, because `scripts/product-name.test.mjs` refuses the word *ring* in user-facing files.
- **2026-11-10** — Check: `app/package.json` loosens nothing: it adds `scripts/relay-knowledge-setup.test.mjs` to the `test` script's list of node tests, so the setup script and the website's copy of `FORMAT.md` are checked.
- **2026-11-10** — Check: `app/self-host/bindings.test.mjs` no longer asks the install's connector for `artifacts KNOWLEDGE`. The install leaves it out because Artifacts needs Workers Paid, and its server then answers that the web is not set up. Each other binding of the connector is still checked.
- **2026-11-10** — Built: the memory table, its columns and tags, note topics, the knowledge web pass, the plugin's copy, and the docs; the staging start repository is made. A second look found five problems (a fact id shared by two computers, a spec line on phone keys, a stale wiki count, two missing tests); all are fixed. Saved for the CI check and the staging trial.
- **2026-11-10** — The staging trial found that the real Artifacts handle gives its git address only through `info()`, so the pass had no address and `sync` stopped; the route now reads it there, and the test's stand-in handle works the same way. Every other step of the trial passed. A pass shows as one Artifacts event on each sync, and a sync with nothing new makes no pull.

## Capabilities

### New Capabilities
- `relay-knowledge-web`: each person's memory table in the database and its columns, their topic pages in the web, the person's own rules for both, a computer's and any plugin's access, and the plugin's copy of the web.

### Modified Capabilities
- `relay-person-spaces`: deleting an account also deletes the memory table and the knowledge web.
- `relay-api`: the web API searches and reads the memory table, finds notes by topic, and a computer's key adds facts, changes the memory table's columns, and changes the topics of facts and notes.
- `relay-ai-connector`: the connector searches and reads the memory table.

## Impact

- New server route `POST /v1/knowledge/access` in the Relay Everything server, with an `ARTIFACTS` binding in `app/wrangler.relay.jsonc` (namespaces `relay-everything-knowledge` and `relay-everything-knowledge-staging`).
- `app/worker/apps/relay/account.ts`: delete the repository with the account.
- `schema/space-migrations/0016_memory.sql`: the memory table, its columns, and topics on notes; `POST /v1/memory/{id}/tags`, `POST /v1/notes/{id}/tags`, `GET /v1/notes?tag=`; routes `POST /v1/memory`, `GET /v1/memory`, `GET /v1/memory/{id}`, `GET` and `POST /v1/memory/columns`; `memory` and `read_fact` tools in the connector (`app/worker/relay-mcp/inputs.ts`, `answers.ts`, `api.ts`).
- `plugin/bin/relay.mjs`: `facts`, `fact <id>`, `add-facts`, `columns`, `change-columns`, `tag`.
- `scripts/relay-knowledge-setup.mjs`: makes the namespaces and the start repository.
- `schema/knowledge/README.md`, `schema/knowledge/FORMAT.md`: the start pages.
- `plugin/bin/knowledge.mjs`, `plugin/lib/config.mjs`: the computer's copy, a git pass helper.
- Site: a new page `site/src/content/docs/api/knowledge-web.md`, with a part for people who build their own plugin; `npm run relay:api-doc`; self-host page notes the paid plan.
- Wiki: `wiki/stack/relay-knowledge-web.md`, linked from `wiki/relay-spaces.md`.
