---
name: relay-update
description: Update Relay Everything's copy in this project to the newest release, and keep the person's own edits. Use for /relay-update, "update Relay Everything", or when a Relay Everything line says to type /relay-update.
allowed-tools: Bash(node:*)
---

# Update Relay Everything

Each command runs Relay Everything's copy in this project, `.agents/relay/`. When that folder is missing, there is no copy to update: tell the person that `/relay:move` moves Relay Everything into this project, and stop. Never install the copy unless the person asks.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it. In Codex's sandbox, the command can not reach GitHub.

1. Check for a new release:

   ```bash
   node "$(git rev-parse --show-toplevel)/.agents/relay/update.mjs" check
   ```

   On `up_to_date=<version>`, tell the person the copy is up to date, and stop.
2. Make the plan. It writes nothing:

   ```bash
   node "$(git rev-parse --show-toplevel)/.agents/relay/update.mjs" plan
   ```

   Tell the person, in a few plain lines: the two versions, how many files the release changes, which of their own edits stay (`keep`), which files merge cleanly with their edits (`merge`), and each clash (`clash`). Do not list each file unless they ask.
3. For each clash, show the person both sides in plain words, then ask: *keep mine*, *keep the release's*, or *keep both*. Read the clash with:

   ```bash
   node "$(git rev-parse --show-toplevel)/.agents/relay/update.mjs" show <path>
   ```

   The lines between `<<<<<<< yours` and `=======` are the person's; the lines from `=======` to `>>>>>>> release` are the release's. A clash in a script they can't read: suggest *keep the release's*.
4. Ask *Update to <version>?* Run `apply` only on a yes, with one `--choose` for each clash: `mine`, `release` or `both`.

   ```bash
   node "$(git rev-parse --show-toplevel)/.agents/relay/update.mjs" apply --choose <path>=mine
   ```

5. Tell the person the version it prints after `updated=`, and that the changed files are in their project to look at and commit as they like.

Never run `apply` without the person's yes, and never change a file of the copy by hand during an update.
