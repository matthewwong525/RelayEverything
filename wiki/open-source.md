# Open source

Relay is one public repository, [matthewwong525/RelayEverything](https://github.com/matthewwong525/RelayEverything), under the [MIT license](../LICENSE). Part of [the wiki](README.md); the rule is in the Relay section of [`AGENTS.md`](../AGENTS.md).

## What is public, and what is not

Everything in the repository is public: the server and web app in `app/`, the phone app in `mobile/`, the website in `site/`, the Claude Code plugin in [`plugin/`](../plugin/README.md) with its marketplace file in [`.claude-plugin/`](../.claude-plugin/marketplace.json), the ring in `cad/` and `pcb/`, and the plans and this wiki. `vendor/` keeps each library's own license.

These stay in Cloudflare, never in the repository: memory, company knowledge, notes, keys, and health and location data. A plan or wiki page is for anyone to read: write no person's phone number, address, email, health or place in it.

The IDs in `.agents/.wong-stack.json` and `app/wrangler.jsonc`, such as the account, Access app and database IDs, are not keys: Access still guards every route.

## The public check

[`scripts/public-check.mjs`](../scripts/public-check.mjs) refuses what must not go public. It names the file, and the commit for history, never the value:

- a key file or private note by its name: `.env` and `.dev.vars` files (not their `.example` copies), Apple and Android signing files such as `.p8`, `.p12`, `.jks` and `.mobileprovision`, a `*.private.*` file, or a `notes/` folder;
- text shaped like a key, such as a GitHub, AWS or Slack token, or a private key block;
- a value from `.env` or `app/.dev.vars` on this computer, but `CLOUDFLARE_ACCOUNT_ID`.

| Mode | What it reads | Where it runs |
|---|---|---|
| `--tree` (the default) | each file Git tracks or would track, as it is now | the Test job on GitHub, with no `.env`, and `npm test` in `app/`, which adds this computer's `.env` values |
| `--history` | each file in each commit that any ref reaches, and each commit message | by hand, before history goes anywhere new |
| `--notes` | lines in `openspec/`, `wiki/` and Markdown files of each commit that name a health or location value, a phone number, a street address, or an email no commit author uses | by hand: a list for a person to read; it never fails |

On `result=refused`, take the private detail out of the file. A refused file in history stays public in every copy once pushed: removing it means rewriting history, which changes every commit ID, so it waits for the person's decision. Never weaken the check to let a file through.

The [Relay website's guard](relay-website.md#what-the-guard-refuses) uses the same rules, and adds its own.

## Phone builds

A change to `mobile/` runs [`mobile-ci.yml`](../.github/workflows/mobile-ci.yml) on GitHub: the Flutter tests, then the Android file, kept with the run. A publish to `main` makes a release, tagged `mobile-v<version>+<build>`; the website's *Android app* link opens the latest one. The iPhone build skips until the repository has the App Store Connect secrets that [`.env.example`](../.env.example) names. [`mobile/README.md`](../mobile/README.md) has the steps.

## Run your own server

Anyone can run Relay in their own Cloudflare account: [`self-host/SETUP.md`](../self-host/SETUP.md) is the guide an AI follows, over [`self-host/setup.mjs`](../self-host/setup.mjs). An install deploys the same Relay files as this repository's app, through its own entry, [`app/worker/relay-only.ts`](../app/worker/relay-only.ts), and its own page build, `npm run build:relay-only`. It carries none of WongStack.

- **A new Relay binding goes in the install too.** Add it to [`self-host/wrangler.template.jsonc`](../self-host/wrangler.template.jsonc) beside [`app/wrangler.jsonc`](../app/wrangler.jsonc); [`bindings.test.mjs`](../self-host/bindings.test.mjs) fails, by name, on one the install lacks, or else every install breaks at its next update.
- **A Relay migration reads only `relay_` tables.** An install applies every migration, so WongStack's tables are there but empty.
- **Relay has no end-to-end encryption.** Data lives on a Relay server or only on the phone. A person who wants more control runs their own server.
- **A device key only adds data.** It reads nothing on any server, so a person's data stays theirs: [Keys](https://relayeverything.com/api/keys/).

## Pull requests from outside

Anyone can open a pull request. Its checks run with none of the project's keys, and nothing deploys from it: [CI on GitHub Actions](stack/github-actions.md#where-the-deploy-key-is) says why.
