# Tasks

## 1. Server: list chats with no words

- [x] 1.1 Make `query` optional in `search_chats` (`app/worker/relay-mcp/inputs.ts`) and in `answers.ts` call `chatPage` with no words and `lines: []` when it is left out; say so in the tool's description; test a week's list with no words, its paging, and that words still filter, in `app/worker/relay-mcp/tools.test.ts` and `api.test.ts`
- [x] 1.2 Run `npm run relay:api-doc` in `app/`, and check the website reference shows `q` as not required on `GET /v1/chats`

## 2. Plugin: the deterministic parts

- [x] 2.1 Write `plugin/lib/headless.mjs` (the Claude Code and Codex command lines of the design, the 30-minute stop, `RELAY_SAVE=0`, `RELAY_BUILD_RUN=1`, `RELAY_BUILD_MODEL`) and test both command lines and the app pick from the hook's environment in `plugin/test/headless.test.mjs`
- [x] 2.2 Write `plugin/bin/build.mjs` `work`: chats with no `q`, quiet over 1 hour and past the read record, notes not in it, newest first, at most 20 and 100, with `left` counts, and notes only on a server that answers `400`; test against the fake server in `plugin/test/build.test.mjs`: a new chat, a grown chat read from its seq, a chat in progress left out, the caps, and an old server
- [x] 2.3 Add `build.mjs` `chat`, `note`, `notes`, `facts`, `add-facts`, `tag` and `done` on `relay.mjs`'s `api` and `parseArgs`, with no health, day, place, point, calendar or photo command; `done` appends to `.relay/read.log`; test each, that an unknown command such as `day` is refused, and that a resend keeps one fact by its `clientId`
- [x] 2.4 Add `build.mjs` `check-facts`: for each candidate, the live facts that share a tag and the closest word matches, at most 5 each; test against the fake server
- [x] 2.5 Add `build.mjs` `related <topic>`: the topics that share facts, sources or notes with it, at most 10, ranked, each with counts by kind, a sample fact and whether a page already links the other; test against the fake server and a made-up copy: shared tags on one fact, a shared chat, a shared note, a link already there, and a topic with nothing shared
- [x] 2.6 Add `build.mjs` `run`: write `tried`, sync, read and append the day's claim in `.relay/builds.log`, commit, sync, stop when another computer's line is earlier; start the agent; stop it after 30 minutes; append the `done` line with counts; sync; test the claim with two made-up copies joined by union merge, a lost claim stopping before any read, and the done line, in `plugin/test/build.test.mjs`
- [x] 2.7 Add `build.mjs` `status`, `off`, `on` and `now`, kept in `build.json` in the Relay Everything folder; test each, and that `status` makes no network call
- [x] 2.8 Start `build.mjs run` detached from `hook.mjs session-start` on a connected computer when the build is on, `RELAY_SAVE` is not `0`, `RELAY_BUILD_RUN` is unset and today is not `tried`; test the first chat of the day, a second chat, a turned-off computer, a build run's own start, and a computer not connected, in `plugin/test/hook.test.mjs`
- [x] 2.9 From review: `note`, `notes` and `work` give a note only its own fields, never `placesNearby` or `day`, tested against a fake that answers as the real `GET /v1/notes/{id}`; `remove-page` for a join, with its refusals; `related` counts only `relay:chat/` sources, tested with two topics that share only a day; `new=` names topics first used in the run, tested with a topic on notes only over two runs; `run` gives a web with an old default `FORMAT.md` the new one, kept in `plugin/build/FORMAT.md` and checked against `schema/knowledge/FORMAT.md`, and keeps a changed one

## 3. Plugin: the AI's parts

- [x] 3.1 Write `plugin/build/PROMPT.md`, `reader.md` and `gardener.md` by the design: read `FORMAT.md`, groups of up to 4 chats and 25 notes, at most 4 readers at a time, the gate, note topics, `done` per item, every topic a fact or note touches, pages side by side, `related` links with words that say how, the look-back and its links at each new topic, joins, splits over 30 live facts into linked pages, `README.md`, broken links, and no health value or place; and the Codex prompt that does the same steps in order; `run` builds the `--agents` JSON from them; test that each file names only `build.mjs` commands that exist and stays under 6000 characters, in `plugin/test/skills.test.mjs`
- [x] 3.2 Write `plugin/skills/build/SKILL.md` for `/relay:build [off|on|now]`, and check it in `plugin/test/skills.test.mjs`
- [x] 3.3 Change `schema/knowledge/FORMAT.md` and the website's copy: the `.relay/` line, pages side by side with hyphen names, a big topic split into linked pages, and links between connected topics; keep a web's existing folders readable in `plugin/lib/topics.mjs` (test unchanged); and check `scripts/relay-knowledge-setup.test.mjs` still matches them
- [x] 3.4 Bump the plugin to 0.5.0 in `plugin/.claude-plugin/plugin.json`; add *Your web builds itself* to `plugin/README.md`

## 4. Docs

- [x] 4.1 Update the website pages `site/src/content/docs/connections/claude-code.md` (the daily build, `/relay:build`, the allowance it uses) and `site/src/content/docs/api/knowledge-web.md` (the `.relay/` record; chats listed with no words)
- [x] 4.2 Add *How the web is built* to `wiki/stack/relay-knowledge-web.md` (trigger, claim, read record, the narrow command, the helpers, how to try it) and link it from `wiki/stack/relay-chats.md`

## 5. Checks

- [x] 5.1 Run `node --test plugin/test/*.test.mjs`, `npm test` in `app/`, `claude plugin validate plugin`, `node scripts/product-name.test.mjs` and `node scripts/public-check.mjs`; all pass
- [x] 5.2 Live trial on staging, by `wiki/stack/relay-chats.md#try-it-on-staging`: a test person with sample chats and notes, the plugin from this checkout in a scratch Claude Code home, connected by the form; start a chat and see the build start and the chat not wait; after it ends, see facts with sources, notes with topics, side-by-side topic pages, at least one link between two topics that share a chat, and `README.md` in the web, no folder made, nothing in the web or memory with a health value or a place, `/relay:build` counts, and a second chat start no build; then run once in Codex the same way; delete the test person and their web after
- [x] 5.3 `/save` after the checks, and the trial in 5.2 matches the scenarios in the spec
