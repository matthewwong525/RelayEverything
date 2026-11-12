# Relay Everything's memory and knowledge web

Each Relay Everything person has a memory of facts, a table in their own [space](../relay-spaces.md), and a knowledge web of topic pages, a git repository in Cloudflare Artifacts that only their computers reach. This page tells how the server keeps both, part of [the Cloudflare stack](README.md). The website's [Memory and knowledge web](../../site/src/content/docs/api/knowledge-web.md) page tells a person and a plugin builder how to use them.

## The memory

- The tables come from [`0016_memory.sql`](../../schema/space-migrations/0016_memory.sql). Only [`memory.ts`](../../app/worker/apps/relay/memory.ts), and the [memory store](#the-memory-store) beside it, write them.
- A person's columns are values in `relay_memory_columns`, not SQL columns. A fact's values are JSON in `fields`. So a column change needs no migration, and no caller's text becomes SQL: a name is checked by pattern, and a filter binds its value.
- A fact is only added. A replace sets the old fact's `replaced_by` in the same batch, and that is the only update. Only deleting the account deletes a fact.
- Only a computer's key (`agent` reach) adds facts, changes columns and changes topics. An API key and the [AI connector](relay-ai-connector.md) read. A phone's key is refused before the web API runs.

### The memory store

The plugin's copy of WongStack memory reaches the same table through its own store, not the `/v1/memory` routes.

- [`memory-routes.ts`](../../app/worker/relay-mcp/memory-routes.ts) answers `/v1/memory/v2/<request>` before `/v1/`'s own routes, only for a computer's key, with WongStack's `serve()` from [`interface.mjs`](../../.agents/skills/memory/store/interface.mjs). The caller is always the admin of the key's own space, so the person sees all of it. Any other key gets 403.
- [`relay-memory/store.ts`](../../app/worker/relay-memory/store.ts) answers the twelve requests. [`0019_memory_store.sql`](../../schema/space-migrations/0019_memory_store.sql) adds memory's number `n` beside the `f…` id, its slug, session, author, owner, sharing and own sources, and the tables for sessions, runs and topic definitions. The store gives the older facts, which name no owner, to the person on each call.
- **Five kinds.** `kindSql` in [`memory.ts`](../../app/worker/apps/relay/memory.ts) reads an older kind as its new one when it reads: `open` as `thread`, `preference` as `feedback`, and `fact`, `decision` and `plan` as `project`. No row's words change. The store refuses an older kind on a new fact; `POST /v1/memory` still takes one, so an older plugin keeps working.
- **Transcripts.** A transcript memory sends goes to the person's sealed files at `memory/transcripts/<session id>`, and deleting the account removes it. With none kept, the store gives the saved Relay Everything chat for that session as text.
- **The daily build skips a chat memory read**: `GET /v1/chats` marks it `memory: true`, because both would save the same facts. Memory read a chat when its session row is `captured`, or a fact names its session: memory's chat end writes a row before it captures.
- [`relay-memory/store.test.ts`](../../app/worker/relay-memory/store.test.ts) runs WongStack's own store check, `checkStore`, against the space. A change to the store passes it first.

## The knowledge web

- **Namespaces.** The live server and connector bind `KNOWLEDGE` to `relay-everything-knowledge`, staging to `relay-everything-knowledge-staging`, in [`wrangler.relay.jsonc`](../../app/wrangler.relay.jsonc) and [`wrangler.relay-mcp.jsonc`](../../app/wrangler.relay-mcp.jsonc). The Worker holds no Cloudflare token.
- **The start repo.** Each namespace has a repo named `start`, holding [`schema/knowledge/`](../../schema/knowledge/README.md)'s `README.md` and `FORMAT.md`. A person's web is a fork of `start`, named `p-<personId>`, made on their computer's first ask ([`knowledge.ts`](../../app/worker/apps/relay/knowledge.ts)). A fork can't be filled from the Worker, as it can't push git objects. A later change to `start` reaches only new webs.
- **The setup script.** [`scripts/relay-knowledge-setup.mjs`](../../scripts/relay-knowledge-setup.mjs) `[--staging]` makes the namespace and `start` when missing, and pushes the two pages with a ten-minute pass. It reads `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the primary worktree's `.env`. [`publish-relay-server.mjs`](../../scripts/publish-relay-server.mjs) runs it before each environment's deploys ([the Workers and their order](../relay-spaces.md#the-workers-and-their-order)), so it is never missed.
- **The pass.** `POST /v1/knowledge/access` answers the web's git address and a write pass for one hour. *Turn off* stops the key at once, but can't call back a pass already given: it ends within the hour. A server with no `KNOWLEDGE` binding, or no `start` repo, answers `501 not_set_up`; a fork still running answers `503 try_again`.
- **The copy.** The plugin's [`knowledge.mjs`](../../plugin/bin/knowledge.mjs) keeps the copy in `knowledge/` in the plugin's folder. It gives the pass to git only as `GIT_CONFIG_*` environment values, never in an argument, a file or the remote. It syncs at most once every 15 minutes, unless the copy has changes or the person adds `--now`, because each sync costs Artifacts operations. A page both computers changed keeps both: text by joining the lines (`merge=union`), any other file with the web's copy beside it as `<name>.other`.
- **Delete.** Deleting the account deletes the person's repo after their space ([`account.ts`](../../app/worker/apps/relay/account.ts)). A person with no web passes.

## How the web is built

The person's own AI builds the memory and the web once a day, on their computer, with [`build.mjs`](../../plugin/bin/build.mjs). The server only stores: it calls no model. The website's [Your web builds itself](../../site/src/content/docs/connections/claude-code.md#your-web-builds-itself) tells a person what it does.

- **The trigger.** At `SessionStart` on a connected computer, the [hook](../../plugin/bin/hook.mjs) starts `build.mjs run` detached on the first chat of the computer's day, and `knowledge.mjs sync` on the others. It writes `tried` in `build.json` before it starts, so a second chat that day starts nothing, even when the build fails. `RELAY_BUILD_RUN` marks the build's own process, so its chat starts no build. A chat with `RELAY_SAVE=0` starts neither.
- **The claim.** The build syncs the copy, appends `<day> <ISO> <name> <id>` to `.relay/builds.log`, syncs, and builds only when its line is the day's earliest. The loser stops. `* merge=union` joins both computers' lines with no clash. A lock file in `build/` stops two builds on one computer.
- **The read record.** `.relay/read.log` has `chat <id> <seq>` and `note <id>` lines. A chat is read from its highest `seq`, so a chat that grew is read again from there. `build.mjs work` lists chats quiet for an hour whose last message is past the record, and notes not in it, newest first: at most 20 chats and 100 notes. It lists chats with `GET /v1/chats` and no `q`, so an older server that needs words answers 400, and the build reads notes only.
- **The narrow command.** The build's AI may run only `build.mjs`, which has no health, place, calendar or photo command, and gives a note only its own fields, by name: never its place, the places near it or its day's health. A join removes the old page with `build.mjs remove-page topics/<name>.md`, the one delete it has, which refuses any path outside `topics/`. Claude Code runs as `claude -p --permission-mode dontAsk --allowedTools … "Bash(node <build.mjs>:*)"` with all hooks off, so the build's chat is never saved. That grant refuses a heredoc or a `<` whose text holds `{`, and a `cd`, a loop or a variable, so the helpers give `check-facts` and `add-facts` their JSON list as one quoted argument. Codex runs as `codex exec` in its `workspace-write` sandbox, with network on and only the copy and `build/` writable. [`lib/headless.mjs`](../../plugin/lib/headless.mjs) builds both commands. The run stops after 30 minutes.
- **The helpers.** In Claude Code, [`PROMPT.md`](../../plugin/build/PROMPT.md) starts up to 4 `reader` helpers at a time, then one `gardener` ([`reader.md`](../../plugin/build/reader.md), [`gardener.md`](../../plugin/build/gardener.md)), passed with `--agents`. Codex does both jobs itself, in order, from [`CODEX.md`](../../plugin/build/CODEX.md). A reader checks each candidate fact with `check-facts` before `add-facts`: new, changed (`replaces`), or the same (dropped). Each fact's `clientId` is a hash of its sources and text, so a resend stores it once. The gardener links topics that `related` ranks as sharing facts, chats or notes, on one page only.
- **The end.** The build counts its own run log in `build/run.log`, appends `<day> done facts= replaced= notes= chats= new=` to `builds.log` (`new=` names topics first used in the run: no page, and no earlier `new=`), syncs, and writes what is left to read in `build.json` for `/relay:build`.
- **Try it.** On a [scratch home](relay-chats.md#try-it-on-staging) connected to staging, with a few saved chats and notes, run `node plugin/bin/build.mjs now`, or start a chat. Watch `build/run.log`, then `/relay:build` for the counts, and read `topics/` in the copy. Run it twice to see that nothing is read again.

## Cost

Artifacts needs Workers Paid. There is no charge for each repo. 10,000 operations a month are free, then $0.15 for each 1,000. A sync is about 2 to 3 operations. In Artifacts analytics, each sync's pass shows as one `token_create` event, a sync with nothing new makes no pull, and a read of a repo makes no event. Cloudflare's pricing names only create, push, pull and clone as billed operations.

## Move a WongStack memory in

A WongStack project, such as WongOS, moves its memory into the person's space once with [`scripts/import-wongstack-memory.mjs`](../../scripts/import-wongstack-memory.mjs). Run it on a computer that `/relay:connect` connected: it writes with that computer's key.

```sh
node scripts/import-wongstack-memory.mjs --from <WongStack checkout> --profile <old store's profile> --dry-run
node scripts/import-wongstack-memory.mjs --from <WongStack checkout> --profile <old store's profile>
```

- **It only reads the source.** It opens the checkout's own memory store, with the profile `--profile` names, else the checkout's own, and sends only read requests. A source that refuses every write still works, so the old store stays as a read-only backup.
- **Numbers stay.** The first run moves the space's own facts above the source's highest number, so fact #628 stays #628. The space refuses that first step when memory has used it already.
- **Run it again to catch up.** A later run sends no first step. It skips each fact it imported before, adds only the new ones, and gives a new fact a new number when the old one is taken. It prints each changed number.
- **What comes with each fact:** its date, author, owner, kind, topics, sources and replaced-by link, its chat's session row, the topic definitions, and the transcript, kept as `memory/transcripts/<session id>`.
- **The server side** is [`relay-memory/import.ts`](../../app/worker/relay-memory/import.ts): `POST /v1/memory/import` takes the status, the first step, a chunk of up to 200 facts, or the finish, by the body's shape, and `POST /v1/memory/import/transcript?session=<id>` takes one transcript. A fact keeps `client_id` `import:<old number>`, so a resent chunk stores once.
- **The check.** The run compares the space's counts of imported facts, live and in all, by kind, with the source's `stats`. It exits 1 and names each count that differs. `--dry-run` prints the source's counts and sends nothing.
