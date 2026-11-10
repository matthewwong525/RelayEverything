# Tasks

## 1. Reads

- [ ] 1.1 Write `plugin/lib/topics.mjs` (topics, summaries and links from the copy; the match) and test it with a made-up copy in `plugin/test/topics.test.mjs`: top level only, a folder topic, a page with no summary, no copy, a clear match on a whole name and on a last part, a weak match, at most 3, and no match
- [ ] 1.2 Print the topic list in `hook.mjs session-start` and add `hook.mjs prompt` with a `UserPromptSubmit` entry in `plugin/hooks/hooks.json`; start `knowledge.mjs sync` on its own at session start; test the list and its caps, the project's topic, an empty copy printing nothing, a computer not connected, and the prompt match, in `plugin/test/hook.test.mjs`
- [ ] 1.3 Add the `topic <name>` command: page, links both ways, facts, notes and up to 3 chats in one answer, with `errors` for a failed part and `page: null` when only facts exist; test against the fake server in `plugin/test/relay.test.mjs`
- [ ] 1.4 Add the `points` command to `plugin/bin/relay.mjs` (`points <id>` and `--from/--to`), and test both forms against the fake server in `plugin/test/relay.test.mjs`
- [ ] 1.5 Add the `around` command (`around <note id>` or `--at <time>`, `--hours` 1 to 12, default 2): note first, then day, notes, places, calendar and the hours' health in parallel, one JSON answer with `errors` for a failed part; test a note, a time with no offset, a time with an offset, a window over 12 hours, and a failed part, in `plugin/test/relay.test.mjs`
- [ ] 1.6 Add `points`, `around` and `topic` to the usage line, and check `node plugin/bin/relay.mjs` with no command prints it
- [ ] 1.7 Make `projectRoot` in `plugin/lib/transcript.mjs` resolve a git worktree to its main repository (through the `.git` file's gitdir and `commondir`), falling back to the worktree path; test a plain repo, a worktree, a broken link, and that `/relay:saving off` in the main repo holds in a new worktree, in `plugin/test/transcript.test.mjs` and `plugin/test/skills.test.mjs`

## 2. Skill and docs

- [ ] 2.1 Rewrite `plugin/skills/ask/SKILL.md`: the new commands, a short *Start from your topics* part (the list, the added topic lines, `topic <name>`, then a fact's source, then raw data by its time), a *Follow the threads* table (topic, fact, note, day, stay or trip, saved chat), when to stop, and naming sources; widen its description's triggers; check with `plugin/test/skills.test.mjs`, which names each command the skill lists
- [ ] 2.2 Bump the plugin to 0.4.0 in `plugin/.claude-plugin/plugin.json`, and update `plugin/README.md` *Ask about your data* and *Turn saving off* (it holds in every worktree)
- [ ] 2.3 Update the website page `site/src/content/docs/connections/claude-code.md` *Ask about your data* with the topic list, a topic pull and an around-a-note example, and `wiki/stack/relay-chats.md` where it lists the plugin's reads

## 3. Checks

- [ ] 3.1 Run `npm test` in `plugin/`, `node scripts/product-name.test.mjs` and `node scripts/public-check.mjs`; all pass
- [ ] 3.2 Install the plugin from this checkout in a fresh Claude Code (`claude plugin marketplace add <checkout>`, `claude plugin install relay@relay`), connect this computer with `/relay:connect` (the person clicks Connect), add a test topic page to this computer's copy, start a new chat and see the topic list, ask a question that names the topic and see its summary added, and ask a real question about a note's context: the AI reads around the note and names its day, place and event
- [ ] 3.3 `/save` after the checks, and the live trial in 3.2 matches the scenarios in the spec
