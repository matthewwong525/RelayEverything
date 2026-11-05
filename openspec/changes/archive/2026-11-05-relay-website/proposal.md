# Relay website

**Status:** ready-to-ship
**Branch:** awful-seahorse
**Open questions:** none

## Why

Relay is meant to be open: other people should be able to read what it is, set it up, and build on it. Today everything about it sits in this private project, so nobody else can read it, and the steps to set up a phone or the Pebble webhook live only in chat.

## What Changes

- **A public Relay website.** Anyone can open it at relayeverything.com, with no login. The home page says what Relay is: a way to get your own notes, health and location off your phone and devices, into a place you choose, where your own AI can read them. Its three cards are the parts: the phone app collects, webhooks send to your own database, and an MCP connection lets your AI read it. The ring comes lower, as one way to take notes. It links to the Android app, TestFlight and the app's code. Tap *Docs* or the menu to read the docs.
  ```live
  folder: prototypes/relay-site
  height: 760
  ```
- **Docs for everything in Relay.** One menu holds every page, with a search box:
  | Section | Pages |
  |---|---|
  | Get started | What you need; install the app; connect a phone; set up the Pebble webhook |
  | Use the app | Notes; health; location; settings |
  | Connections | Send your data to your own database; connect your AI (MCP); an example skill and tables to copy |
  | Server API | Keys; each route with its fields and an example; the Pebble webhook |
  | The ring | How it works; parts and battery; the board; 3D models and test prints |
  | Privacy | What is kept, where, and how to turn each part off |
- **The docs keep up by themselves where they can.** The API pages are made from the server's own route list, so a change to a route that leaves its page old fails the checks. Each later Relay change updates its own page in the same change: sending to your database and the AI assistant connection get their pages when they are built.
  ```mermaid
  flowchart TD
    A["A Relay change"] --> B["Its page changes too"]
    A --> C["API pages made from the routes"]
    B --> D["publish"]
    C --> D
    D --> E["Privacy check"]
    E -->|"clean"| F["Website updated"]
    E -->|"finds a key or private detail"| G["Stopped, file named"]
  ```
- **Nothing private reaches the website.** It is a separate small site that can't reach your notes, health or places, and your private site keeps its login. Before each update, a check refuses any page that holds a key, a value from your private settings, an email address, or your private site's address. It names the file, never the value.
- **It updates after each publish, like the app's public copy.** After a change is published, the same step that copies the app to GitHub also updates the website. A plan's preview gets its own look-first address.

Non-goals: a memory platform (no plugin format, no `relay init`, no access roles: you use your own database and tools), renaming Relay inside the pages, downloads of the 3D models or board files, a blog, comments, and analytics.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are in `.env`.
- **The domain relayeverything.com**: Ready, it is in your Cloudflare account with no records yet.
- **OpenSCAD for the ring pictures**: Ready, installed on this computer.
- **The Relay app first version, published**: Ready when it publishes. It is being built in the chat "Set up the Relay ring repo", and this build starts after it; nothing to do from you.

## Capabilities

### New Capabilities
- `relay-website`: the public Relay website: its pages, the API reference made from the routes, the privacy check, and how it updates and previews.

### Modified Capabilities

## Impact

- New: `site/` (Astro Starlight project, `site/wrangler.jsonc` for Workers `relay` and `relay-staging`, assets only, no bindings), `scripts/publish-relay-site.mjs` and its test, `app/worker/apps/relay/api-doc.ts` and its test.
- Changed: `scripts/publish-relay-app.mjs` (exports its guard for reuse), `AGENTS.md`'s Relay section (run the site step after each publish; each Relay change updates its page), `wiki/` (a page on the website), `.gitignore` (`site/dist`, `site/.astro`).
- Cloudflare: two Workers on the account's workers.dev subdomain, static files only.
- Depends on: `relay-app-first-version` (routes, contract, device keys, screens).

## Decision log

- **2026-11-05** — Asked who should read Relay's docs → chose a public site, hosted on a Cloudflare Worker in this project.
- **2026-11-05** — Asked what the docs cover → chose everything: the app, set-up, the server API, sending to your database, the AI assistant connection, and the ring's parts, board and 3D models.
- **2026-11-05** — Asked how the public site sits next to the private site → chose its own small site, separate from the private one.
- **2026-11-05** — Asked which address → the person said it is Relay's main website, not only docs; then chose the free address relay.matthewwong525.workers.dev for now.
- **2026-11-05** — Asked whether to build the site with Vite and React like WongStack or with Astro Starlight → chose Starlight: it runs on Vite, can use React where needed, and brings the menu, search and pre-built pages a public site needs.
- **2026-11-05** — Assumed: the site updates from this computer after each publish, beside the app's GitHub copy, not inside the check runner, because the check runner's deploy step is shared WongStack code that deploys only the main app, and changing it would conflict with each WongStack update.
- **2026-11-05** — Assumed: the site's own tests and the privacy check run in the publish step and in `/apply`, and the API page's freshness test runs in the main app's checks, because the checks run only the main app's suite.
- **2026-11-05** — Assumed: the docs never name the private site's address; the API pages say *your Relay server*, because the address isn't needed to read them and it is private.
- **2026-11-05** — Assumed: the ring pages describe and show the ring with pictures rendered from the 3D models, with no model or board files to download, because `cad/` and `pcb/` are not public yet.
- **2026-11-05** — Assumed: the ring pages give a summary, and the build-level numbers stay in `cad/README.md` and `pcb/PLAN.md`, because a second full copy goes stale.
- **2026-11-05** — Assumed: pages for sending to your database and for the AI assistant connection are written by those changes when they are built; until then the home page lists them as coming, because their plans are not settled.
- **2026-11-05** — Assumed: previews deploy to a second Worker, relay-staging, because a preview version can't be uploaded to a Worker that doesn't exist yet, and the live one must not change before publish.
- **2026-11-05** — Build: `relay-app-first-version` is on `main` (8007f8e, archived at `openspec/changes/archive/2026-11-05-relay-app-first-version/`); this branch moved forward to it with no merge commit.
- **2026-11-05** — Build, differences from the plan found in the published app: the Pebble app's menus are *Index 01 Settings* → *Webhook* → *Hold & talk*, *Sign requests*, *Both* and *Send test event*, not the prototype's *Index*, *Signing*, *Transcription and Recording* and *Send test*; `GET summary` is for a signed-in person only, not a device key; `GET audio` is a bare handler with no description; no Relay action has `errors` or `examples` yet, so the route page shows them only when an action gains them; the iPhone build is not in TestFlight yet (it waits for the paid Apple membership).
- **2026-11-05** — Assumed: the Pebble steps use the menu names from the published site page's Pebble dialog (`app/src/apps/relay/Setup.tsx`), not names read from the Pebble app on the phone, because the build can't open the phone; check them on the phone at the preview.
- **2026-11-05** — Assumed: the notes page is at `app/your-notes/`, not `app/notes/`, because the app guard that the site reuses refuses any `notes/` folder as private notes, and the guard must not be weakened.
- **2026-11-05** — Assumed: the route page says who can call each route, from `DEVICE_ROUTES`, now exported by `app/worker/apps/relay/device.ts`, because a device key reaches all routes but `summary`; and `GET audio` gets its own page, *Recordings*.
- **2026-11-05** — Assumed: the site guard refuses any `workers.dev` address but `relay` and `relay-staging`, and every UUID, long hex value and email in `app/wrangler.jsonc`, because that covers the main Worker's addresses, the Access IDs and audiences and any later ID with no list to keep.
- **2026-11-05** — Assumed: the guard refuses any email address in pages, JSON, the search index and sources, but in script bundles (`.js`, `.mjs`) only the private site's own emails, because Starlight's and Pagefind's search scripts credit their translators by email, and a page's own text always lands in its HTML and the search index too.
- **2026-11-05** — Assumed: `npm test` in `site/` builds the site and then runs its tests, and the publish step runs install, test and the guard, because the tests check the built pages.
- **2026-11-05** — Assumed: the iPhone install steps say the build is not in TestFlight yet and point to *Build it yourself* in relay-app, and the home page links to the TestFlight app as the private site page does, because no public invite link exists yet.
- **2026-11-05** — Check: `site/package.json` is new: its `test` script builds the site and runs `site/tests/`, the site's own checks. No check was loosened.
- **2026-11-05** — Asked in chat to hook the website up to relayeverything.com, the new name → the live site moves to relayeverything.com and www.relayeverything.com, its workers.dev address off; previews stay on relay-staging.matthewwong525.workers.dev.
- **2026-11-05** — Assumed: "the new name" means the website's address; the pages still call the product Relay, because a product rename changes every page and wasn't asked.
- **2026-11-05** — Assumed: the live deploy after publish runs by the Relay rule in `AGENTS.md`, not as task 6.5, because a task can't wait for the publish that needs every task done first.
- **2026-11-05** — Assumed: the preview deploys from an unsaved snapshot of the tree (a commit object no branch points to), because the publish step reads a commit and saving belongs to `/save`.
- **2026-11-05** — Assumed: the app's full `npm test` is judged by the check run, not on this computer, because here 71 tests in files this change doesn't touch time out under a load of about 100, and the same tests fail the same way on the published code.
- **2026-11-05** — Saved for final acceptance: built, reviewed (two fixes: a test that a refusal stops the update, nested nullable lists in the API page), previewed at relay-staging; the live domain is relayeverything.com.
- **2026-11-05** — Asked through the "Relay Everything" chat to present Relay as a way to get your own data off your phone into a place you choose, where your own AI reads it, not as a smart ring first and not as a memory platform → the hero, cards, *How your data travels*, menu order and Connections page changed; the ring stays as one way to take notes; Connections lists the webhooks, MCP and an example skill and tables as coming.
- **2026-11-05** — Assumed: the hero picture is a phone, a database and an AI mark, not the ring, and the menu puts Connections before Server API and the ring last, because the ring is no longer the headline.
- **2026-11-05** — Archive checkpoint: the person approved the data-first home page and its preview; the change is archived for publish at relayeverything.com.
