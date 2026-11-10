# Design

## Context

Part 1 (`knowledge-web`, PR #102) made the memory table, note topics, and each person's web in Cloudflare Artifacts, with the plugin's copy in `knowledge/` under the Relay Everything folder (`plugin/bin/knowledge.mjs sync`). The copy's `.git/info/attributes` sets `* merge=union`, so lines from two computers join. Part 3 (`plugin-follows-threads`, PR #103) reads the copy at `SessionStart` and `UserPromptSubmit` (`plugin/bin/hook.mjs`, `plugin/lib/topics.mjs`) and starts a detached `hook.mjs sync`. `relay.mjs` already maps `facts`, `add-facts`, `tag`, `chat`, `notes` to `/v1/`. `GET /v1/chats` needs `q` today (`search_chats` in `app/worker/relay-mcp/inputs.ts`). The memory store's `lib/headless.mjs` holds the headless command line for both apps; the plugin can't import it, because each app copies only `plugin/`.

## Goals / Non-Goals

**Goals:** a daily, unattended build on the person's computer; a deterministic work list, claim, read record and gate look-up; two helper prompts; one narrow command for the agent; a switch and a status.

**Non-Goals:** reading a note's later edits; a pass that joins or replaces facts already stored; moving an existing folder to side-by-side pages; a page in the phone or web app; any model on the server; reading health, places, calendar or photos; a build on a schedule with no chat (the first chat is the trigger); changing the topic hooks of part 3.

## Decisions

### Trigger: the first chat start of the local day

`hook.mjs session-start`, on a connected computer, after it starts `sync`, starts `build.mjs run` detached when all hold: the build is not off on this computer (`build.json` in the Relay Everything folder), `RELAY_SAVE` is not `0`, `RELAY_BUILD_RUN` is unset, and `build.json`'s `tried` day is not today in the computer's zone. `run` first writes `tried`, so a second chat that day starts nothing, even when the run fails. The hook's work stays a file read and a spawn: no network, within its 10 seconds.

### The day's claim, in the web

`run` syncs (`knowledge.mjs sync --now`), then reads `.relay/builds.log` in the copy, one line per claim: `<day> <ISO time> <computer name> <computer id>`. If a line for today exists, it stops. Else it appends its line, commits, and syncs again; after that sync, the earliest line for today wins, and a loser stops. Union merge joins both computers' lines, so the tie-break needs no server. A narrow race costs one doubled build at most, and the gate drops doubled facts.

Alternative: a claim route on the server. Rejected: a new table and route for one line a day, when the web already syncs.

### The read record, in the web

`.relay/read.log` holds one line per item read: `chat <id> <seq>` (the last message read) or `note <id>`. The newest line for a chat wins. Lines only grow, so union merge joins any two copies. `build.mjs done` appends a line as each item finishes, so a run stopped at 30 minutes keeps what it did. The `.relay/` folder is not a topic: `topics.mjs` reads only `topics/`, and `FORMAT.md` gets one line that says `.relay/` is the builder's record.

### The work list is code

`build.mjs work` lists, newest first:

- chats from `GET /v1/chats` with no `q`, `from` 90 days back and paged on for older, whose `lastAt` is over 1 hour ago and whose `messages` is past the read record's seq; at most 20;
- notes from `GET /v1/notes?from=&to=`, newest first, not in the read record; at most 100.

It prints JSON with each item's id, its read-from point and its day, plus how many are left (`left.chats`, `left.notes`), which `status` shows. The page-on reads stop as soon as the list is full.

### Server: chats listed with no words

`search_chats`'s `query` becomes optional. Without it, `answers.ts` calls `chatPage` with no words and gives each chat `lines: []` (`chatLines` needs a word). The connector's tool takes the same input, so the AI connector can list a week's chats too; its description says so. `npm run relay:api-doc` regenerates the website's reference.

### One narrow command for the agent

The agent gets one Bash grant: `node <plugin>/bin/build.mjs`. Its commands are `work`, `chat <id> --after <seq>`, `note <id>`, `notes --q|--tag`, `facts --q|--tag|--source`, `check-facts`, `related <topic>`, `add-facts`, `tag fact|note <id> --add --remove`, `remove-page topics/<name>.md`, and `done chat|note <id> [<seq>]`. A note reaches the agent with only its own fields, by name: never its place, the places near it or its day's health. `remove-page` removes one `.md` page under `topics/` in the copy and refuses any other path, because the agent's grant can't delete a file and a join must remove the old page. Each reuses `relay.mjs`'s `api` and `parseArgs`. It has no health, day, places, points, calendar or photo command, so the build can't read them. `relay.mjs` stays as it is for the `ask` skill.

### The gate is code that shows, the helper decides

`check-facts` reads candidate facts on stdin and answers, for each, the live facts that share a tag and the closest word matches (`GET /v1/memory?tag=` and `?q=`, at most 5 each). The reader helper then adds, adds with `replaces`, or drops. This mirrors the memory store's write gate. Each fact gets a `clientId` made from its source and text, so a resend after a lost answer stores it once.

### A graph of pages: what code finds, what the helper writes

The default `FORMAT.md` changes from a tree to a graph: pages sit side by side in `topics/`, new names use hyphens (`bike-battery`), and a big topic splits into smaller pages that the first one links, never a folder. A folder or `/` name a web already has stays, because moving a page breaks its tag and its links; `topics.mjs` reads both.

`build.mjs related <topic>` is code that finds the edges. From the topic's live facts (`facts --tag`), it counts: the other tags on the same facts; the other tags on facts from the same sources (`facts --source relay:chat/<id>`, one read for each of at most 10 chats); and the other topics of the topic's notes (`notes --tag`). It answers at most 10 topics, ranked by how much they share, each with the count by kind and one shared fact's text as a sample, and whether either page already links the other (from the copy, as `topics.mjs` reads it). The gardener reads that list and writes a link only where the two are truly related, as a sentence on one page: *The charger cable is the one from the [trip to Ottawa](travel.md).* A page also links a topic wherever its text names it. The link goes on one page only: part 1's one-way rule holds, and `linksIn` in `topics.mjs` gives the other way, so a topic pull shows both.

Readers give a fact or a note every topic it touches, not only the main one, because a shared fact is the edge that `related` finds.

### The agent run

`lib/headless.mjs` copies the memory store's command shape, narrowed:

- **Claude Code:** `claude -p <prompt> --agents <plugin>/build/agents.json --permission-mode dontAsk --allowedTools Read Write Edit Glob Grep Task "Bash(node <build.mjs>:*)" --add-dir <copy> --no-session-persistence --settings '{"disableAllHooks":true}'`, with cwd the copy. The two helpers, `reader` and `gardener`, come from `plugin/build/reader.md` and `gardener.md`; `run` builds the `--agents` JSON from them, so they never show in the person's own agent list.
- **Codex:** `codex exec --ephemeral --skip-git-repo-check --sandbox workspace-write -c sandbox_workspace_write.network_access=true -c 'sandbox_workspace_write.writable_roots=[<copy>]' -c approval_policy="never" <prompt>`, cwd the copy. The prompt tells it to do the readers' work, then the gardener's, in order.

The app is the one the starting chat came from: Codex when the hook's environment has `CODEX_HOME` or `PLUGIN_ROOT` without `CLAUDE_PLUGIN_ROOT`, else Claude Code. The child gets `RELAY_SAVE=0` and `RELAY_BUILD_RUN=1`. `RELAY_BUILD_MODEL` sets `--model` or `-m`. `run` kills the child after 30 minutes, then syncs, so done work is sent.

### The prompt and the helpers

`plugin/build/PROMPT.md` (the lead): read `FORMAT.md`; run `work`; split chats into groups of up to 4 and notes into groups of up to 25; start one `reader` per group, at most 4 at a time; then one `gardener` with the topics the readers touched and the ones they made new.

- **`reader.md`:** read each item from its read-from point; pick facts worth keeping by `FORMAT.md`'s kinds; run `check-facts`, then `add-facts`; tag each note; `done` each item. Never copy a health value or a place; link `relay:day/<day>` for time.
- **`gardener.md`:** for each touched topic, read its facts by tag and write the page by `FORMAT.md`; for each touched topic, run `related` and link the connected pages; for each new topic, search facts and notes by its words (`facts --q`, `notes --q`, at most 50 each), tag those that fit, and link it from the pages it connects to; join same topics (tag the old facts and notes with the kept topic, remove the old tag, remove the old page with `remove-page`, and point links at the kept page); split a topic with over 30 live facts into smaller linked pages beside it; update `README.md`; fix broken links. Then `run`, not the AI, appends one line of today's counts to `.relay/builds.log` (`<day> done facts=18 replaced=3 notes=40 chats=12 new=garden,sam`), counted from what `build.mjs` added and tagged in this run. `new=` names the topics first used in this run: a topic is known when the copy has its page or an earlier `done` line named it new. Before the agent starts, `run` gives the copy the new default `FORMAT.md` when its `FORMAT.md` is an old default word for word, by its SHA-256; a `FORMAT.md` the person changed stays. The plugin keeps the default in `plugin/build/FORMAT.md`, and a test checks it equals `schema/knowledge/FORMAT.md`.

### The switch and the status

`build.mjs off|on` writes `build.json` on this computer. `status` reads `build.json`, the copy's `.relay/builds.log` and the last `work` counts, with no agent and no network. `now` runs `run` in the foreground, skipping the `tried` check but not the claim. The skill `plugin/skills/build/SKILL.md` maps `/relay:build [off|on|now]` to these.

## Risks / Trade-offs

- [A build uses the person's model allowance] → caps of 20 chats and 100 notes, a 30-minute stop, an off switch, and `RELAY_BUILD_MODEL` for a smaller model.
- [Headless Claude Code in the copy has no trusted folder] → `-p` skips the trust prompt; the grant names every tool, and `dontAsk` refuses the rest.
- [Codex's sandbox can't reach the network by default] → `network_access=true` for the copy only, as the memory store's run does.
- [Union merge of a page edited on two computers] → only one computer builds a day; part 1 keeps both versions on a clash.
- [Flat pages make the start list long: every topic is top level] → the chat-start list already keeps the 40 newest; `README.md` lists every topic, and links, not the list, lead to the rest.
- [Too many links make every page link every other] → `related` gives at most 10, ranked, and the gardener links only real connections, with words that say how.
- [A wrong topic] → tags can change; the next build's gardener joins and re-tags, and the person can ask the AI to change one.
- [The first build on a big past finds little to join] → the look-back at each new topic, and later builds, pull older items in.

## Migration Plan

Plugin 0.5.0 ships with the server change. An older server answers `400` to `GET /v1/chats` with no `q`: `work` then lists notes only and says chats wait for a newer server. Turn off: `/relay:build off`, or uninstall; facts and tags already added stay, as all facts do.
