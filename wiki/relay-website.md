# The Relay Everything website

The Relay Everything website is Relay Everything's public home page and docs, at <https://relayeverything.com> (and `www.`), open to anyone with no login. Part of [the wiki](README.md); the rule to update it after each publish is in the Relay Everything section of [`AGENTS.md`](../AGENTS.md).

## Where it lives

- **Code:** [`site/`](../site/), an [Astro Starlight](https://starlight.astro.build) project of its own, separate from the main app in `app/`. Its pages are Markdown in `site/src/content/docs/`; the home page is `index.mdx`.
- **Hosting:** two Workers from [`site/wrangler.jsonc`](../site/wrangler.jsonc), static files only, with no bindings: `relay` is live on the custom domains `relayeverything.com` and `www.relayeverything.com` (its workers.dev address is off), and `relay-staging` shows a change before it publishes. The site can reach no note, key or private page.
- **Checks:** `npm test` in `site/` builds the site, then checks that each menu entry and each link opens a page, and that no page names a private address. The main app's checks don't run these; [the publish step](#update-and-preview) does.

## Add or change a page

1. Write the page in `site/src/content/docs/<section>/<page>.md`, with a `title` and a `description`.
2. Add it to the menu in [`site/sidebar.mjs`](../site/sidebar.mjs). The menu order is the reading order.
3. Link other pages relatively, such as `../keys/`, so a new address later breaks no link.
4. Name the server *your Relay Everything server* and write its address as `https://<your-relay-server>/...`, never the private site's address.

Describe Relay Everything as a way to get your own notes, health and location off your phone and devices, into a place you choose, where your own AI can read them. Do not describe it as a memory platform: Relay Everything has no plugin format, no `relay init` and no access roles, and developers use their own database and tools. A connection that is not built yet shows as *Coming*, with no steps. Say the app keeps notes on the phone by default, and sending to your Relay Everything server is an add-on the person turns on: never say the app syncs everything from the start.

The home page is for conversion: few words and one call to action, with pictures that show the data going to an AI such as ChatGPT or Codex and symbols for what the phone sends. Keep each picture calm. Matthew turned down the 2026-11-08 drafts in turn as *too wordy … too many CTA*, then *too basic*, then *a bit too much going on*. Ask early how many pictures he wants and how many words.

A page's folder can't be named `notes/`: [the public check](open-source.md#the-public-check) refuses any `notes/` folder as private notes, so the notes page is `app/your-notes/`.

No text people read names the ring: it is gone. The notes it sent stay in people's spaces, and a page that must name them calls them *older recorded notes*. [`scripts/product-name.test.mjs`](../scripts/product-name.test.mjs) fails on the word *ring* in any file people read outside the wiki; a quoted value such as `'ring'` and a hyphenated name such as `relay-ring` pass. Call the shape that fills round *New note* a *circle*. An old `/ring/` address opens the home page through `site/public/_redirects`.

The pictures of the Relay Everything page in `site/src/assets/web/` are screenshots of the Flutter app in a browser, with sample notes and no real person's data. [On a computer](../site/src/content/docs/app/on-a-computer.md) owns how the page works. Keep each file name when you take a new screenshot, so no page needs an edit. A change to the page's look or layout takes new screenshots in the same change.

## Legal pages and the contact address

The terms and policies for the shared server are pages in `site/src/content/docs/`. A page whose text is not in force yet opens with a `:::caution[Draft: not in force]` box and marks each gap, such as the company's name, as `[LEGAL-TODO: …]`. `site/tests/site.test.mjs` fails when a page in the menu, or a page the home page links to, holds a gap, and when a page with a gap has no draft box. So fill every gap before you add a legal page to the menu. The rules are in [the legal pages spec](../openspec/specs/relay-legal-pages/spec.md).

The site guard refuses every email address, so the contact address lives on the server, not here: `RELAY_CONTACT_EMAIL` in [`app/wrangler.relay.jsonc`](../app/wrangler.relay.jsonc) puts it on the sign-in screen and the account card. A page tells people to write to the address on the shared server's sign-in page. Never weaken the guard to put the address on the site.

## The API pages

[Routes](../site/src/content/docs/api/reference.md) is made from the server's own route list by [`api-doc.ts`](../app/worker/apps/relay/api-doc.ts): each described route's method, path, fields, errors and example, and who can call it. After a route change, run `npm run relay:api-doc` in `app/`: it also writes the webhook format's public schema, `site/public/webhooks/v1.schema.json`, from [`format.ts`](../app/worker/apps/relay/webhooks/format.ts). The main app's checks fail when the page or the schema differs from what the code makes. A route with no description in the contract, such as `GET audio`, needs its own page and an entry in `HAND_PAGES` in `api-doc.ts`.

## Update and preview

[`scripts/publish-relay-site.mjs`](../scripts/publish-relay-site.mjs) exports `site/` at a commit, installs, tests and builds it, runs the guard, and deploys. It prints one `result=` line: `deployed url=...`, `ready` (a dry run), `empty` (no `site/`), `refused <file> (<why>)` or `failed <step>`.

| When | Command |
|---|---|
| After each publish | `node scripts/publish-relay-site.mjs` |
| To preview a change | `node scripts/publish-relay-site.mjs --ref HEAD --staging`, then open <https://relay-staging.matthewwong525.workers.dev> |
| To check without a deploy | `node scripts/publish-relay-site.mjs --ref HEAD --dry-run` |

It deploys with `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the primary `.env`. To take the site down, run `npx wrangler delete --name relay` (and `relay-staging`) in `site/`. A failure another chat hands you can already be fixed on main: run the dry run with `--ref origin/main` before you plan a fix.

## What the guard refuses

The guard reads every source file and every built file, the search index included, as text. Pictures are checked by name only. It refuses, naming the file and never the value:

- a key file, text shaped like a key, or a value from `.env`, by [the public check](open-source.md#the-public-check);
- an email address;
- a `*.cloudflareaccess.com` address;
- a `workers.dev` address of any Worker but `relay` and `relay-staging`;
- an ID from [`app/wrangler.jsonc`](../app/wrangler.jsonc): every UUID or long hex value, such as the Access app IDs and audiences.
- the private site's own domain, each `routes` host in [`app/wrangler.jsonc`](../app/wrangler.jsonc), such as `admin.relayeverything.com`. The public `relayeverything.com` still passes: the guard matches the whole host.

Never weaken the guard to let a page through: take the private detail out of the page.
