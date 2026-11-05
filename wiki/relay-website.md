# The Relay website

The Relay website is Relay's public home page and docs, at <https://relayeverything.com> (and `www.`), open to anyone with no login. Part of [the wiki](README.md); the rule to update it after each publish is in the Relay section of [`AGENTS.md`](../AGENTS.md).

## Where it lives

- **Code:** [`site/`](../site/), an [Astro Starlight](https://starlight.astro.build) project of its own, separate from the main app in `app/`. Its pages are Markdown in `site/src/content/docs/`; the home page is `index.mdx`.
- **Hosting:** two Workers from [`site/wrangler.jsonc`](../site/wrangler.jsonc), static files only, with no bindings: `relay` is live on the custom domains `relayeverything.com` and `www.relayeverything.com` (its workers.dev address is off), and `relay-staging` shows a change before it publishes. The site can reach no note, key or private page.
- **Checks:** `npm test` in `site/` builds the site, then checks that each menu entry and each link opens a page, and that no page names a private address. The main app's checks don't run these; [the publish step](#update-and-preview) does.

## Add or change a page

1. Write the page in `site/src/content/docs/<section>/<page>.md`, with a `title` and a `description`.
2. Add it to the menu in [`site/sidebar.mjs`](../site/sidebar.mjs). The menu order is the reading order.
3. Link other pages relatively, such as `../keys/`, so a new address later breaks no link.
4. Name the server *your Relay server* and write its address as `https://<your-relay-server>/...`, never the private site's address.

Describe Relay as a way to get your own notes, health and location off your phone and devices, into a place you choose, where your own AI can read them. Do not describe it as a smart ring first: the ring is one way to take notes, and it may never ship. Do not describe it as a memory platform: Relay has no plugin format, no `relay init` and no access roles, and developers use their own database and tools. A connection that is not built yet shows as *Coming*, with no steps.

A page's folder can't be named `notes/`: [the app guard](../scripts/publish-relay-app.mjs) refuses any `notes/` folder as private notes, so the notes page is `app/your-notes/`.

The ring pictures in `site/src/assets/ring/` are rendered from `cad/`: run `npm run render-ring` in `site/` when a model changes.

## The API pages

[Routes](../site/src/content/docs/api/reference.md) is made from the server's own route list by [`api-doc.ts`](../app/worker/apps/relay/api-doc.ts): each described route's method, path, fields, errors and example, and who can call it. After a route change, run `npm run relay:api-doc` in `app/`. The main app's checks fail when the page differs from what the routes make. A route with no description in the contract, such as the Pebble webhook, needs its own page and an entry in `HAND_PAGES` in `api-doc.ts`.

## Update and preview

[`scripts/publish-relay-site.mjs`](../scripts/publish-relay-site.mjs) exports `site/` at a commit, installs, tests and builds it, runs the guard, and deploys. It prints one `result=` line: `deployed url=...`, `ready` (a dry run), `empty` (no `site/`), `refused <file> (<why>)` or `failed <step>`.

| When | Command |
|---|---|
| After each publish | `node scripts/publish-relay-site.mjs` |
| To preview a change | `node scripts/publish-relay-site.mjs --ref HEAD --staging`, then open <https://relay-staging.matthewwong525.workers.dev> |
| To check without a deploy | `node scripts/publish-relay-site.mjs --ref HEAD --dry-run` |

It deploys with `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the primary `.env`. To take the site down, run `npx wrangler delete --name relay` (and `relay-staging`) in `site/`.

## What the guard refuses

The guard reads every source file and every built file, the search index included, as text. Pictures are checked by name only. It refuses, naming the file and never the value:

- a key file, text shaped like a key, or a value from `.env`, by the [app guard](../scripts/publish-relay-app.mjs);
- an email address;
- a `*.cloudflareaccess.com` address;
- a `workers.dev` address of any Worker but `relay` and `relay-staging`;
- an ID from [`app/wrangler.jsonc`](../app/wrangler.jsonc): every UUID or long hex value, such as the Access app IDs and audiences.

Never weaken the guard to let a page through: take the private detail out of the page.
