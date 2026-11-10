# Design

## Context

Ring text sits in four kinds of place (see proposal.md, Impact):

- **Hand-written pages**: `site/src/content/docs/**`, `mobile/README.md`, the wiki.
- **Generated pages**: `site/public/api/v1.openapi.json`, `site/public/webhooks/v1.schema.json` and `site/src/content/docs/api/v1-reference.md` come from the server's own descriptions in `app/worker/relay-mcp/` and `app/worker/apps/relay/webhooks/format.ts`. `npm run relay:api-doc` in `app/` writes them, and the same tests fail when they differ.
- **Screens**: the phone app (`account.dart`, `Info.plist`) and the React web page (`app/src/apps/relay/`).
- **Stored data**: `relay_notes.source = 'ring'`, with a sealed recording at `people/<person>/<note>`. This stays as it is.

`scripts/product-name.test.mjs` already lists every file people read (`userFacingFiles`) and reads each by its kind (`readable`): prose for Markdown, strings for code, with code spans, fences and link targets blanked. The ring check reuses both.

Two other plans touch the same files:

- `flutter-web-app` (workspace *spotted-snail*) deletes `app/src/apps/relay/`.
- `landing-page-refresh` (workspace *electric-bobcat*) replaces `site/src/content/docs/index.mdx` with `site/src/pages/index.astro` and modifies the same home page requirement in `relay-website`.

## Goals / Non-Goals

**Goals:**
- No text a person reads names the ring, and a check keeps it so.
- Every older ring note keeps working: the phone pulls it, its recording plays, webhooks and the API carry it.

**Non-Goals:**
- No change to stored data, routes, the `source` value, the audio route, tables or the `relay-ring` folder.
- No change to archived plans, `knowledge/roadmap.md` (its *Pebble ring* is the person's own device), the device check's *Pebble ring*, or worker comments that describe stored ring notes.
- No new docs page.

## Decisions

- **Name the ring's notes *older recorded notes*.** A phone voice note keeps its recording on the phone and syncs as `typed`; only the ring's notes carry a server recording. *Older recorded notes* is true and names no device. Alternative: leave them unnamed. Rejected: the privacy table and the recordings page must say where those recordings are.
- **Keep `source: "ring"` in the API and webhooks, and describe it.** The enum value is code and stays exact; its description changes, such as *Only older recorded notes, or only typed ones.* Alternative: drop the `source` filter. Rejected: it breaks a caller that passes it, for no gain.
- **Old addresses through `site/public/_redirects`.** One line, `/ring/* / 301`. Cloudflare's static assets read `_redirects` from the built folder, and Astro copies `public/` into it. Alternative: let them 404. Rejected: search results and old links still point at those pages for a while. The preview check opens `/ring/board/` on staging to prove it.
- **The ring check lives in `product-name.test.mjs`.** It is a second `test()` over `userFacingFiles()` minus `wiki/`, through `readable()`, refusing `/\bring\b/i` unless the word sits inside quotes or a backtick (`'ring'`, `"ring"`) or follows a hyphen (`relay-ring`, `focus-visible:ring-…`). Markdown code spans and fences are already blanked. The wiki is left out because it is internal knowledge that must describe stored ring notes. Alternative: a new script. Rejected: it would repeat the file list and the reader.
- **The web page loses the *Ring* / *Typed* badge entirely.** The settled rule is that old ring notes show as plain notes; a *Typed* badge alone on every note says nothing. The card's `aria-label` becomes `Note`.
- **The Claude Code example gets a non-ring chat.** `project: "relay-ring"` and the stiffener talk become a plain example, such as `"project": "my-app"` and a question about a test. It is sample data, not a hidden name.
- **Whichever publishes second catches up.** If `flutter-web-app` is on `main` first, skip every `app/src/apps/relay/` task. If `landing-page-refresh` is on `main` first, `index.mdx` is gone: add `site/src/pages` to `PLACES` and read `.astro` as markup, so the check covers `index.astro`, and reconcile the home page requirement against its version, keeping *names no ring*.

## Risks / Trade-offs

- [The check refuses a fair use of *ring*, such as *a ring of the phone*] → Reword it; no such use exists today. An `ALLOWED`-style list can hold a phrase if one is ever needed, with a `Check:` line in that change's Decision log.
- [`_redirects` is not served by the site's Worker setup] → The staging preview proves it before going live; if it fails, drop the file and let the pages 404, logged in the Decision log.
- [The regenerated API files differ in more than the ring words] → Run `npm run relay:api-doc` on a clean tree and read the diff; only the descriptions should move.
- [An iOS permission text change] → It ships with the next TestFlight build by itself; App Store review reads it like any other build.

## Migration Plan

No data moves. Publish, then run `node scripts/publish-relay-site.mjs` and `node scripts/publish-relay-server.mjs`; the server publish carries the AI connector's new words. Roll back by reverting the change: nothing stored depends on it.
