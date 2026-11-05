# Design

## Context

See [proposal.md](proposal.md) for why. This project is on the Artifacts route: its code, checks and deploys live in Matthew's Cloudflare account, with no GitHub Actions. The check runner ([`scripts/check-runner/pipeline.mjs`](../../../scripts/check-runner/pipeline.mjs)) runs the main app's `npm test` in `app/`, then deploys only the main app through `main`'s `cf-build.sh` and `cf-deploy.sh`, which refuse a build naming any other Worker. The main app sits behind Cloudflare Access; its only public paths are a short reviewed list ([the bypass table](../../../wiki/stack/cloudflare-access.md#4-bypass-the-public-surface)).

`mobile/` already reaches the public `matthewwong525/relay-app` through `scripts/publish-relay-app.mjs`, which this computer runs after each publish ([`AGENTS.md`](../../../AGENTS.md)). Its `blocked()` guard refuses key files, key-shaped text and `.env` values.

The content comes from the plan `relay-app-first-version` (its design.md): routes under `/apps/relay/api/*`, per-device Access service tokens, the Pebble webhook's fields and signing, the Flutter screens, and the release and TestFlight links. Ring content comes from [`cad/README.md`](../../../cad/README.md), [`pcb/PLAN.md`](../../../pcb/PLAN.md) and [`pcb/SCHEMATIC.md`](../../../pcb/SCHEMATIC.md).

## Goals / Non-Goals

**Goals:** a public static site in this project; an API reference that can't drift from the routes; a fail-closed privacy guard; one command that updates the site after each publish, and a preview address for builds.

**Non-Goals:** changing the check runner, `cf-build.sh`, `cf-deploy.sh` or the Access bypass list; serving any data; analytics or cookies.

## Decisions

### A separate assets-only Worker, not a public path on the main app

`site/wrangler.jsonc` names Worker `relay` (live on custom domains `relayeverything.com` and `www.relayeverything.com`, `workers_dev: false`) and `env.staging` Worker `relay-staging` (previews), each with `assets.directory: "./dist"`, no `main`, and no bindings; staging keeps `workers_dev: true` and `routes: []`, so it never claims the domain. Astro's `site` is `https://relayeverything.com`, for canonical links and the sitemap. *Alternative:* a `/docs/*` bypass on the main Worker, one address, but it widens the login wall, needs a reviewed core change and the deployment check's table, and runs public pages beside private bindings. Rejected for risk.

Previews use the second Worker because `wrangler versions upload --preview-alias` fails on a Worker that doesn't exist, and the live Worker must not change before publish. Each preview overwrites `relay-staging`; one preview at a time is enough for one person.

### Astro Starlight in `site/`

`site/` is its own npm project: Astro with `@astrojs/starlight`, output `static`. Starlight gives the splash home page (`template: splash`), the sidebar, Pagefind search, light and dark, and the previous/next pager, as plain HTML and a small script. Content is Markdown in `site/src/content/docs/`:

```text
site/
├─ astro.config.mjs        title Relay, sidebar order, social link to relay-app
├─ wrangler.jsonc          relay / relay-staging, assets only
├─ package.json            dev, build, test
├─ src/assets/ring/        PNG renders of the ring models
├─ src/content/docs/
│  ├─ index.mdx            home (splash)
│  ├─ start/               what-you-need, install, connect-a-phone, pebble-webhook
│  ├─ app/                 notes, health, location, settings
│  ├─ ring/                how-it-works, parts-and-battery, board, models
│  ├─ api/                 keys, pebble-webhook, reference.md (made from routes)
│  ├─ connections/         index.md (database, MCP, example skill: coming until built)
│  └─ privacy.md
└─ tests/                  node:test files
```

The home page follows the approved prototype in `prototypes/relay-site/` (hero, three cards for collect, send to your database and let your AI read, *How your data travels*, then the ring as one way to take notes). Starlight's default theme is kept, with Relay's name, a ring mark and an accent colour: one small `custom.css`. *Alternative:* VitePress (Vue) or a mini app in the React main app. VitePress is equal on features; Starlight's splash page and built-in search fit a product home plus docs with less setup. A mini app can't be public without the bypass above.

The docs name the server *your Relay server* and write its routes as `https://<your-relay-server>/apps/relay/api/...`; they never name the private site's address, Access team domain or IDs.

### The API reference is made from the routes

`app/worker/apps/relay/api-doc.ts` exports `apiReference(): string`. It takes the relay app's `routes` from its `api.ts`, runs the shared contract's `registrations()` and `schemas()`, and renders, per described action: method and path, summary and description, an input and output field table (name, type, required, description from `.describe()`), errors, and the first example as JSON. Bare handlers (the Pebble webhook, audio) are listed with a link to their hand-written page.

`api-doc.test.ts` reads `site/src/content/docs/api/reference.md` and asserts it equals `apiReference()`; on a mismatch it fails with *run `npm run relay:api-doc` in app/*. That script (a vitest run with `RELAY_API_DOC_WRITE=1`, or `tsx`, whichever keeps the coverage rule) writes the file. The test lives in the main app's suite, so the check runner enforces it. *Alternative:* hand-written API pages, which go stale silently.

### The privacy guard

`scripts/publish-relay-app.mjs` already exports `blocked(files, secrets)`; the site reuses it and adds a site-only check, `siteBlocked(files)`, in `scripts/publish-relay-site.mjs`: any email address, any `*.cloudflareaccess.com` address, the main Worker's names (`relay-ring`, `relay-ring-staging`) on `workers.dev`, and Access app IDs and AUDs read from `app/wrangler.jsonc`. It scans every file in `dist/` (HTML, JS, JSON, the Pagefind index) as text. Image files are skipped for text checks but names are checked. A hit returns `result=refused <file> (<why>)`, deploying nothing. The Markdown sources are also checked, so `/apply` catches a problem before the build.

### One update command, run after each publish

`node scripts/publish-relay-site.mjs [--ref <commit>] [--staging] [--dry-run]`:

1. Export `site/` at `--ref` (default `origin/main`) with `git archive` into a temp folder; `result=empty` when there is no `site/`.
2. `npm ci`, `npm test`, `npm run build` there; a failure prints `result=failed <step>`.
3. Run the guard on the sources and `dist/`.
4. `wrangler deploy` (or `--env staging`) with `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the primary `.env`; parse the address; `result=deployed url=<address>`. `--dry-run` stops before deploy and prints `result=ready`.

`AGENTS.md`'s Relay section gets: after each publish, run `node scripts/publish-relay-site.mjs` beside `publish-relay-app.mjs` and report both `result=` lines; never weaken the site guard; each change to Relay's app, server, ring or connections updates its website page in the same change. `/apply` previews a site change with `--ref HEAD --staging` and shows `relay-staging.matthewwong525.workers.dev`.

*Alternative:* deploy in the check runner, which would gate the site on CI. It means editing WongStack's shared deploy scripts and their refusal rules, which every `/wong-sync` would conflict with. Revisit if the runner gains a hook for extra Workers.

### Ring pictures

`site/scripts/render-ring.sh` runs `openscad` on `cad/relay-v1-ring.scad` (`part="assembly"`), `cad/relay-click-test.scad` and `cad/relay-wear-test.scad` to PNG at 1200×900, into `site/src/assets/ring/`. The PNGs are committed (small, about 100 KB each) so the publish step needs no OpenSCAD. Re-run it when a model changes. The ring pages give the summary (sizes, battery and life estimate, the six-switch band, hold-to-record, the board's main parts) and say the ring is in design; full numbers stay in `cad/` and `pcb/`.

### Wiki

One page, `wiki/relay-website.md`, linked from [`wiki/README.md`](../../../wiki/README.md): where the site lives, how to add a page, how the API page is made, the update and preview command, and what the guard refuses.

## UX

### Use-case brief
Readers are people curious about Relay, people setting up a Pebble ring or the app, and developers calling the API; Matthew is the first. Done is: a reader learns what Relay is in one screen, or finishes a set-up page and it works. Most visits land on a docs page from search or a link, on a phone or a computer. Reading set-up steps on a phone while tapping in the Pebble app is the common case. Mirrors Starlight's standard docs layout, which readers already know.

### Flow
Home → *Get started* → *What you need* → next pages in order with the pager. Landing from search: the page, with the menu one tap away (☰ on a phone). Search: `/` or the search box → a page.

### Hierarchy
Home: *Get started* is the one primary button; the app links are secondary. Docs page: the title and lead sentence first; the steps; the pager. The sidebar is secondary; *Coming* entries are muted.

### Review
[review.html](review.html): What Changes item 1 is the live prototype of the home page and one docs page, at phone and computer width. Item 2 is the page list.

### Components
Starlight's own header, sidebar, search, page frame, asides (`:::note`), tables, code blocks and pager; its `Card`, `CardGrid` and `LinkButton` on the home page. New: the ring mark, the hero picture (phone, database, AI) and one CSS file for the accent colour. No React and no shared app parts: the site is separate from the main app.

## Risks / Trade-offs

- [The site's tests and guard are not in the check runner] → the publish step runs them and refuses to deploy on failure; `/apply` runs them before preview; the API freshness test is in the main app's suite.
- [The update runs from this computer] → it is the same pattern as the app's GitHub copy, with one reported `result=` line; a missed run leaves the site one publish behind, never wrong in a private way.
- [Docs drift from the app and ring] → the API page is generated; the `AGENTS.md` rule makes each Relay change update its page; ring pages stay summary-level.
- [The Relay app first version changes while being built] → this change builds only after it publishes, from its final routes and screens.
- [A public preview address] → previews pass the same guard; they hold nothing more than the live site will.
- [The token may lack the right to claim a custom domain] → the first live deploy then fails with wrangler's reason and the old site, if any, stays; add Workers Routes and DNS edit for the zone to the token, or add the domain in the dashboard.

## Migration Plan

New site only. First run creates both Workers. To take it down: `wrangler delete --name relay` (and `relay-staging`) from `site/`; nothing else depends on it.

## Open Questions

- The exact Pebble app menu names for the webhook page: read them from the Pebble app on Matthew's phone during the build.
