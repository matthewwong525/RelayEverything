# Your own Claude builds your knowledge web each day: helpers on your computer read your chats and notes into facts and topics, with no AI on the server

**Status:** in-progress
**Branch:** black-owl
**Open questions:** none

## Why

Your memory table and your knowledge web are live, and the AI reads your topics when a chat starts. But nothing fills them yet: no fact is added and no note gets a topic unless you ask. A model on the server costs too much. Your own Claude already runs on your computer, so it can do this work once a day, with no help from you.

## What Changes

- **Once a day, your own Claude builds your web on its own.** The first chat of the day on a connected computer starts the build in the background. Your chat never waits, and you pick nothing: no topic, no tag. The build uses your own Claude, on your own plan. With two computers, only one builds each day.
  ```mermaid
  flowchart TD
    S["First chat today"] --> B["Build starts in the background"]
    B --> R["Helpers read chats and notes"]
    R --> G["A helper writes and tidies pages"]
  ```

- **Helpers read your older chats and notes into facts.** A chat is read when it has been quiet for an hour, so the chat you are in waits for tomorrow. Each helper reads a few chats or notes and adds short facts, each with its topics and a link to the message or note it came from. Before it adds a fact, it looks at the facts you already have: it adds a new one, replaces an old one that changed, or adds nothing.
  ```text
  Chat "Bike battery test", Nov 9, msg 41
    "500 Wh lasted the whole ride"
          ▼ helper
  [decision] Battery is 500 Wh, not 400 Wh.
             #bike-battery  relay:chat/7f3a#41
             replaces: Battery is 400 Wh.
  ```

- **Your notes get topics.** A helper reads each new note and gives it its topics. Your words stay as you wrote them. A note with nothing to keep gets no topic and no fact.
  ```text
  Note  "Charger cable is too short"
        topics  #bike-charger  #travel   ← helper
  ```

- **One helper writes and tidies your topic pages, side by side.** Each topic with facts gets one page that sums them up in plain sentences, and the start page lists your topics with one line each. Pages sit side by side, with no folders. A big topic splits into smaller pages that link to each other, not into a folder. The helper joins two topics that are the same and fixes broken links.
  ```text
  topics/bike.md           links battery, charger
  topics/bike-battery.md   500 Wh; charges in 3 h
  topics/bike-charger.md   cable too short; dock
  topics/travel.md         links bike-charger
  ```

- **Pages link to each other where ideas connect, across topics.** Your web is a graph of linked pages, not a tree. Plain code finds the topics that share a fact, a note or a chat, and the helper adds a link where the two are truly related, with a few words that say how. It also links a topic wherever a page names it. A topic pull then shows the pages it links and the pages that link it, so the AI finds a related idea in another topic in one step.
  ```mermaid
  flowchart TD
    B["bike-battery"] -- "same rides" --> C["bike-charger"]
    S["sam"] -- "lent it" --> C
    C -- "for the trip" --> T["travel"]
  ```

- **A new topic looks back.** When the build makes a new topic, the helper searches your older facts and notes for ones that fit, and adds the new topic to them. It also links the new page from the pages it connects to. So a topic made today also holds what you said last month.
  ```text
  New topic: garden
    looks back ▶ 3 facts, 5 notes from Oct
    each gets #garden
  ```

- **Your past fills in a part each day.** Each build reads the newest unread chats and notes first, up to 20 chats and 100 notes. Older ones follow on the next days until all are read. A record of what was read stays in your web, so nothing is read twice, on any of your computers.
  ```text
  Day 1   newest 20 chats, 100 notes
  Day 2   the next 20 and 100
  …       until all are read
  Then    only what is new each day
  ```

- **Health and places stay where they are.** The helpers can't read your health or your places. A page links to the day of what it sums up, and the AI reads that day's health and places only when you ask. No health value or map point goes into a fact or a page.
  ```text
  Page  "Long ride on [Nov 9](relay:day/2026-11-09)"
        ✗ no heart rate, no route copied
  ```

- **You can see it and stop it.** `/relay:build` says when the last build ran and what it added. `/relay:build off` stops the daily build on this computer, `on` starts it again, and `now` runs one at once.
  ```text
  /relay:build
  Last build: today 09:14, on this computer
    12 chats, 40 notes read
    18 facts added, 3 replaced
    2 new topics: garden, sam
  Still to read: 31 chats, 220 notes
  ```

## What the build needs

- **Nothing.** At the end of the build the AI connects this computer to Relay Everything staging with a test person, runs one build on sample chats and notes, and deletes the test person after.

## Decision log

- **2026-11-10** — Settled before this plan: all AI work runs on the person's computer, through their own Claude and its helpers, with no person in the loop and no AI on the server; once a day, at the first chat of the day, helpers read older chats and notes into facts, tag notes, write and tidy topic pages, and look back when they add a new topic. A note keeps no place of its own; pages link to health and places by time.
- **2026-11-10** — Asked how far back the build reads → chose all of it, a part each day: the newest unread first, up to 20 chats and 100 notes a build, until all are read.
- **2026-11-10** — Assumed: a chat is read once it has been quiet for an hour, and read again from where it stopped when it grows, because the chat in progress is not done, and WongStack's background run waits the same hour.
- **2026-11-10** — Assumed: with two computers, the first to claim the day in the web builds and the other stops, because two builds would add the same facts twice and cost twice.
- **2026-11-10** — Assumed: what was read is kept as lines in the web, under `.relay/`, because the web already syncs between computers and joins lines from both, so no new server table is needed.
- **2026-11-10** — Assumed: the build runs in the app the chat started in, Claude Code with helpers, Codex as one agent that does the same steps in order, because the plugin works in both and Codex's helpers are not sure to run headless.
- **2026-11-10** — Assumed: the build reads and writes only through one plugin command that has no health, place, calendar or photo read, because a tool the helpers can't call can't copy those values.
- **2026-11-10** — Assumed: deterministic code makes the work list, the day's claim, the read record and the gate's look-up of close facts; the AI only decides what a fact says, which topics fit, and what a page says, because the steps that repeat the same way each day need no model.
- **2026-11-10** — Assumed: the build uses the person's normal model, and `RELAY_BUILD_MODEL` can pick another, because WongStack's background run does the same.
- **2026-11-10** — Assumed: the build's own chat is not saved and starts no build, because it would fill the memory with facts about building the memory.
- **2026-11-10** — Assumed: a note is read once; a later edit to its words is not read again in this plan, because the web API gives no time of a note's last edit.
- **2026-11-10** — Assumed: the web API lists chats active in a time without search words, because the build needs every quiet chat, and today the list needs words.
- **2026-11-10** — Assumed: a build stops after 30 minutes, and the next day goes on from what it marked read, because a stuck build should not use the person's plan all day.
- **2026-11-10** — Assumed: `/relay:build off` holds only on this computer, because each computer runs its own Claude on its own plan.
- **2026-11-10** — Asked (the person's own words, on the plan) for the web's pages to be connected as a graph, not a tree, so connected ideas show across topics → chose: pages sit side by side with no new folders, a big topic splits into smaller linked pages, and the build adds links between topics that share a fact, a note or a chat, and wherever a page names a topic.
- **2026-11-10** — Assumed: a fact or a note that touches two ideas gets both topics, because a shared fact is the edge that code finds between two topics.
- **2026-11-10** — Assumed: a page links another page one way, with the other way found by a scan of the copy, as part 1's one-way rule says, because a link written twice goes stale on one side; the topic pull already shows both ways.
- **2026-11-10** — Assumed: new topic names use hyphens, not `/`, such as `bike-battery`, and a folder or a `/` topic that a web already has stays as it is, because a moved page breaks its links and its tag.
- **2026-11-10** — Declined, for now: a pass that joins or replaces facts already stored; the person asked for links between pages instead.
- **2026-11-10** — Assumed: a note's answer has no topics, so `related` reads them with an empty topic change, which changes nothing, because no read route gives a note's topics.
- **2026-11-10** — Assumed: `build.mjs` strips a note's `place` from `note`, `notes` and `work`, because a note answer carries one and the build must never see a place.
- **2026-11-10** — Assumed: `build.mjs` has a `columns` command, and the prompts map each `relay.mjs` command in `FORMAT.md` to `build.mjs`, because `FORMAT.md` says to fill the memory's columns.
- **2026-11-10** — Assumed: the hook writes `tried` before it starts the build, and starts no sync of its own that day, because the build syncs first and two syncs at once would race for the copy.
- **2026-11-10** — Assumed: `/relay:build now` starts the build on its own in the background, not in the chat, because a chat's command would time out in 30 minutes.
- **2026-11-10** — Assumed: a lock file in the plugin's `build/` folder stops two builds at once on one computer.
- **2026-11-10** — Assumed: the build counts its work from a run log in `build/`, which the next run clears, so Codex's sandbox can write only the copy and that folder.
- **2026-11-10** — Assumed: `run` lists the work first, starts no agent when nothing is left to read, and keeps what is left in `build.json` for `/relay:build`.
- **2026-11-10** — Assumed: a claim line is `<day> <ISO> <name> <id>`, with a random 8-character id kept in `build.json`, as a computer's name can have spaces and two computers can share one.
- **2026-11-10** — Assumed: a chat's read record keeps its highest `seq`, so two computers' lines for one chat agree.
- **2026-11-10** — Assumed: `work` reads every page of chats and notes, up to 200 pages, with no window of days, so the `left` counts are exact.
- **2026-11-10** — Assumed: Claude Code's build allows both `Task` and `Agent`, so the helpers start under the old and the new name of the tool.
- **2026-11-10** — Assumed: the app is also picked as Codex from a `rollout-` transcript or `CODEX_THREAD_ID`, as Codex gives a hook both.
- **2026-11-10** — Assumed: the made-up web of the knowledge tests moved to `plugin/test/fake.mjs`, so the build tests use the same one.
- **2026-11-10** — Assumed: the save test now expects the build to start at the first chat of the day; the behavior changed, and the test checks the same thing as before.
- **2026-11-10** — Assumed: `build.mjs` gives a note only its own fields, by name (id, title, source, text, time, device, audio, files, topics), not only without its `place`, because one note's answer also has the places near it and its day's steps, sleep, heart rate and workouts, and a newer server can add more.
- **2026-11-10** — Assumed: `build.mjs remove-page topics/<name>.md` removes one page in the copy for a join, and refuses any path outside `topics/`, with `.` or `..`, not `.md`, or through a link, because the Claude Code build's grant can't delete a file.
- **2026-11-10** — Assumed: `related` counts shared sources only for chats, as the design says, because a day is shared by everything on it, and a note's topics count on their own.
- **2026-11-10** — Assumed: `new=` names the topics first used in the run: a topic is known when the copy has its page or an earlier `done` line named it new, because a topic on notes only has no page and would be new each day; the record is already in `builds.log`, which syncs between computers.
- **2026-11-10** — Assumed: a web whose `FORMAT.md` is still the old default word for word gets the new default at the start of a build, and a `FORMAT.md` the person changed stays as it is, because webs from part 1 keep the old copy, which says to make folders. The plugin can't read `schema/`, so it keeps the default in `plugin/build/FORMAT.md` and the old default's SHA-256; a test checks the copy equals `schema/knowledge/FORMAT.md`.
- **2026-11-10** — Built: the chat list with no words on the server, `build.mjs` and its helpers, the daily start, `/relay:build`, the side-by-side rules and the docs. A second look found five problems (a note read passed its nearby places and the day's health, the gardener could not delete a joined page, a shared day counted as a link, a notes-only topic showed as new each day, and older webs kept the folder rule); all are fixed and reread. Saved for the CI check before the staging trial.

## Capabilities

### New Capabilities
- `relay-knowledge-build`: the daily build of the person's memory and knowledge web by their own AI on their computer: when it starts, what it reads, the gate, note topics, side-by-side topic pages, the links between connected topics, the look-back, the read record, the one-computer claim, the limits, and the person's switch.

### Modified Capabilities
- `relay-api`: the web API lists saved chats active in a time without search words.
- `relay-knowledge-web`: the default rules keep topic pages side by side and split a big topic into linked pages, not a folder; pages link connected topics.

## Impact

- New `plugin/bin/build.mjs`: `work`, `chat`, `notes`, `facts`, `check-facts`, `related`, `add-facts`, `tag`, `done`, `status`, `on`, `off`, `now`, and the detached `run` that claims the day, starts the agent and syncs.
- New `plugin/build/`: the build's prompt and the two helpers, `reader.md` and `gardener.md`.
- New `plugin/lib/headless.mjs`: the agent's command line, copied from the memory store's shape.
- `plugin/bin/hook.mjs`: the first chat start of the day starts `build.mjs run`.
- New skill `plugin/skills/build/SKILL.md`; `plugin/.claude-plugin/plugin.json` version 0.5.0.
- `app/worker/relay-mcp/inputs.ts`, `answers.ts`: `search_chats` and `GET /v1/chats` take no words; `npm run relay:api-doc`.
- `schema/knowledge/FORMAT.md` and the site's copy: the `.relay/` folder, side-by-side pages, hyphen names, and links between connected topics.
- Site: `site/src/content/docs/connections/claude-code.md` and `api/knowledge-web.md`; plugin `README.md`.
- Wiki: `wiki/stack/relay-knowledge-web.md` gets the build; `wiki/stack/relay-chats.md` links it.
