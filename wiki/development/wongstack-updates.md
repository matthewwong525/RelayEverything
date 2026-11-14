# What a WongStack update keeps here

This page lists what each [`/wong-sync`](../../.agents/skills/wong-sync/SKILL.md) update of this project must keep, because Relay Everything uses some of WongStack's files in its own way. The general update steps are in [make WongStack your own](../stack/customizing-wongstack.md#update-at-two-levels).

- **The public plugin list stays Relay Everything only.** `.claude-plugin/marketplace.json` is Relay Everything's public list, not WongStack's. Keep WongStack's memory, Daily and Access entries out of it: each person who installs Relay Everything sees that list. WongStack 61.0.0 deletes its own copy of the file, and its catch-up names the file; keep the file here.
- **Each WongStack hook runs once.** Since WongStack 61.0.0, `.claude/settings.json` runs each module hook one time, with no `enabledPlugins` keys. Do not add a module plugin back: Matthew wants one copy of each hook, also in trusted folders.
- **The Relay Everything copy carries WongStack memory.** [`plugin/`](../../plugin/README.md) holds a copy of WongStack memory, and `plugin/test/memory-copy.test.mjs` keeps it equal to `.claude/skills/memory/`. An update that changes memory also updates the copy and gives Relay Everything a new version.
- **The plugin's Codex step stays off.** Running it adds Relay Everything to Codex for every folder on the computer.
- **The background helper installs in the main folder.** After an update that changes the helper, run `node .claude/skills/reply-link/scripts/helper.mjs install` in the main `/root/relay-ring` folder, not in a workspace: a workspace is deleted when its chat closes. Install it at a quiet minute, not on a minute that ends in 0 or 5, when the line-up runs.

Part of [development](README.md).
