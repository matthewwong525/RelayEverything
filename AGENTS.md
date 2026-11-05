# AGENTS.md

The assistant reads this file first in every chat. Add your own rules above or below the block.

## Relay ring

This project is Relay, a smart ring: `cad/` holds the OpenSCAD models, `pcb/` the KiCad board, `vendor/` copied libraries (see [`vendor/README.md`](vendor/README.md)), and `mobile/` the Flutter phone app.

- **STL files are exports.** Git ignores them; rebuild from the `.scad` models in `cad/`.
- **The whole project is public.** It lives at https://github.com/matthewwong525/RelayEverything under the MIT license; `vendor/` keeps its own licenses. Never commit a key, a signing file or a private note: `node scripts/public-check.mjs` refuses them on every change, and `--history` reads every past commit. `result=refused` names the file, never the value: take the private detail out; never weaken the check. Memory, company knowledge, notes, keys, health and location stay in Cloudflare, never in the repository. [Open source](wiki/open-source.md)
- **Phone builds run on each pull request** that changes `mobile/`: the Flutter tests, then the Android file with the run. A publish to `main` makes a release of RelayEverything, tagged `mobile-v<version>+<build>`. The iOS build skips until the repository has the App Store Connect secrets that `.env.example` names.
- **Device keys.** Each phone and the Pebble app sends with its own Access service token. Make, list and turn off keys with `node scripts/relay-device-key.mjs create|list|revoke --name "<device>"` (add `--staging` for previews). A new key shows once: as a QR code in the person's own terminal, and on a private page under `~/.relay-everything/device-keys/`. Never copy a key into chat, a note or a file in the repository. The site refuses every other service token except the checker: when you make a new checker token (`CF_ACCESS_CLIENT_ID` or `CF_ACCESS_STAGING_CLIENT_ID`), put the SHA-256 of its Client ID in that environment's `RELAY_CHECKER_SHA256` in `app/wrangler.jsonc` too. The check before publishing prints the new value.
- **The phone app is offline by default.** Notes stay on the phone until the person turns on *Send to your Relay server* in Settings; with it off, the app makes no network call. Health and location history exist only while sending is on: the phone reads and keeps none while it is off.
- **Health and location data** live only in the site's database, in `relay_health` and `relay_locations`, and on the person's phone until they send. Never put them in memory, the wiki or the repository.
- **The website is public.** `site/` is the Relay website, https://relayeverything.com, with no login. After each publish, run `node scripts/publish-relay-site.mjs` and report its `result=` line. `result=refused` names a file holding a key, an email address, or the private site's address or IDs: take it out of `site/` and publish again; never weaken the site guard. To preview a change to `site/`, run `node scripts/publish-relay-site.mjs --ref HEAD --staging` and show relay-staging.matthewwong525.workers.dev. Each change to Relay's app, server, ring or connections updates its website page in the same change; a route change runs `npm run relay:api-doc` in `app/`. The docs never name the private site's address: write `<your-relay-server>`. [The Relay website](wiki/relay-website.md)
- **JLC print orders** are handled in the chat named Relay ring, not here.

<!-- WONG-STACK:BEGIN — generic conventions, copied verbatim into each install: no repo-specifics. -->

## Where context lives

Before a change, **read the owning doc**: start at [`wiki/README.md`](wiki/README.md) and follow the links down. Four memory surfaces, one job each; no fact on two:

- `openspec/changes/<slug>/`: the plan and why it has this shape. Ships, then archives.
- The memory store, outside git: each session's facts. Superseded, never edited. A digest loads at session start ([convention](wiki/development/memory.md)).
- `wiki/` and `knowledge/`: repeatable knowledge ([philosophy](wiki/agent-knowledge-center.md), [style](wiki/wiki-style.md)). Canonical and curated; grows from use.
- `openspec/specs/` and the archive: what shipped, never changed.

Before substantial work, `memory.mjs recall <question>` finds [evidence](wiki/development/document-retrieval.md); read originals. Keep `areas <path>` for warnings and `openspec list` for plans.

Credentials for this computer's own tools sit in the git-ignored `.env` at the primary worktree, mapped by the committed, values-blank `.env.example`. For any business service, start with `node scripts/company-api.mjs services`, then `list --q`, `describe`, `call`: the app holds those keys. Don't stub a call or ask for a key in chat: declare a missing one, then [send the key link](wiki/development/secrets.md#receive-a-key-through-a-private-link).

## Rules

- **Always use ASD-STE100 Simplified Technical English** for user-facing prose and documentation. Best-effort compliance is sufficient without the full standard. Keep code, commands, identifiers, quotations, and prescribed text exact.

- **Do plain requests directly.** Research, errands, reminders, and questions need no verb; ask only for a needed answer. Repo edits end with *publish it?*: [the change loop](wiki/development/the-change-loop.md).
- **One task, one workspace.** A finished task closes its Paseo workspace through `/close`, with no question but a routine or app offer; a new task opens a new workspace: [one task, one workspace](wiki/development/the-change-loop.md#one-task-one-workspace).
- **Offer a schedule or a mini app when a finished task will clearly come back**: they said it recurs, or memory shows they asked before. Offer once, in the closing question; remember a no: [offer a routine or an app](wiki/development/the-change-loop.md#offer-a-routine-or-an-app).
- **Keep messages short and plain**, in [our voice](wiki/voice.md): a few lines, more only if asked. Name git, OpenSpec, or CI only if the person asks or must act. Plans, questions, and reports use [plain words](.agents/skills/explore/references/asking-the-user.md#write-in-plain-words) for everyone.
- **A person just asks to build or change code; you run the verbs** `/explore → /plan → /apply → /save → /ship`, plus `/continue`, `/close`, `/verify`, `/improve-code`, `/schedule`, and `/wong-sync`. Asked with no verb, start at `/plan`, never asking *Plan it?* or naming the step, and stop at the plan and at the preview: [just ask](wiki/development/the-change-loop.md#just-ask). A verb also serves [work that changes no repo file](wiki/development/the-change-loop.md#verbs-for-any-work), with a confirm per outward action.
- **Print the plan's link whenever you make or change a plan**, above any closing question: [print the plan's link](.agents/skills/explore/references/asking-the-user.md#print-the-plans-link).
- **Build a new standalone page or tool as a mini app**: its own folders in the main app, served at `/apps/<name>/`, through the same loop: [mini apps](wiki/stack/mini-apps.md).
- **The WongStack skills own all git; OpenSpec never runs git.** `/apply` reads branch changes but makes none: [the change loop](wiki/development/the-change-loop.md).
- **CI is the gate when present, else PR review; a local check is only a pre-check**: [the gate](wiki/development/the-change-loop.md#the-gate).
- **Send an improvement upstream by hand**: [contributing](wiki/contributing.md).
- **A scheduled `/improve-code` writes a plan and waits**: [code improvement](wiki/development/repository-improvement.md).
- **Write repeatable knowledge when you learn it**: what will help a different, future task, placed by [the wiki rules](wiki/wiki-style.md#repeatable-knowledge); a `knowledge/` page is [saved at once](wiki/stack/company-knowledge.md#save-a-page). A change's specifics stay in its proposal.
- **Company actions and memory reads:** [discover only what you need](wiki/stack/service-catalogue.md) through the shared helper; company calls use employee login, memory keeps its installed access; [skills call actions](wiki/stack/company-api.md#build-a-skill-on-actions). Before using a key directly, read its notes page from `services`; add a call you worked out there. An MCP server [goes through the app](wiki/stack/company-api.md#use-an-mcp-server-through-the-app), never in a chat's settings.
- **API keys/tokens:** [human steps](wiki/development/secrets.md#api-token-website-steps); never browse.
- **Browse as the person; show key moments; ask for what needs them**: [logins](wiki/development/browsing.md#saved-browser-logins), [saving passwords](wiki/development/passwords.md), [pictures](wiki/development/browsing.md#show-what-the-browser-is-doing), [asking](wiki/development/browsing.md#when-a-step-needs-you), [buying](wiki/development/shopping.md).
- **Path-scoped conventions load from [`.claude/rules/`](.agents/rules/)**; an agent that doesn't auto-load them reads those whose `paths:` match its files.

<!-- WONG-STACK:END -->
