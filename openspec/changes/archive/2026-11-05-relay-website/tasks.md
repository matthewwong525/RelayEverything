# Tasks

## 1. Before the build

- [x] 1.1 Confirm `relay-app-first-version` is published on `main` (its archive exists under `openspec/changes/archive/`) and bring `main` into this branch; stop and report if not
- [x] 1.2 Read its final `app/worker/apps/relay/api.ts`, handlers, `scripts/relay-device-key.mjs`, `mobile/` screens and release links, and list any difference from the plan's design in this change's Decision log

## 2. Site project (site/)

- [x] 2.1 Create `site/` as an Astro Starlight project (static output), `site/wrangler.jsonc` with Workers `relay` and `relay-staging` (assets only, no bindings, `workers_dev: true`), and add `site/dist/`, `site/.astro/` and `site/node_modules/` to `.gitignore`; verify `npm run build` in `site/` writes `dist/index.html`
- [x] 2.2 Set the title, ring mark, accent `custom.css`, social link to relay-app and the sidebar from design.md; build the splash home page from `prototypes/relay-site/`; verify the built home page has the three app links and the *Get started* button
- [x] 2.3 Add `site/scripts/render-ring.sh` and commit the PNG renders of the V1 assembly, click test and wear test in `site/src/assets/ring/`; verify each PNG is under 300 KB

## 3. Docs pages (site/src/content/docs/)

- [x] 3.1 Write *Get started*: what you need, install the app (Android release, TestFlight), connect a phone (device key, QR), set up the Pebble webhook (route, custom headers, signing, Transcription and Recording, test event); verify each step against the published app and the Pebble app's menus
- [x] 3.2 Write *Use the app*: notes, health, location, settings, matching the published screens
- [x] 3.3 Write *The ring*: how it works (hold to record, raised edges), parts and battery, the board, 3D models and test prints, with the renders; summary only, numbers matching `cad/` and `pcb/`
- [x] 3.4 Write *Server API* hand pages: keys (service token headers, revoke) and the Pebble webhook (multipart fields, signature, retries, dedupe)
- [x] 3.5 Write *Connections* (sending to your database and AI assistants, both marked coming unless published by now; if published, write their pages from their specs) and *Privacy* (what is kept, where, how to turn each part off)
- [x] 3.6 Add `site/tests/` (node:test): every sidebar entry resolves to a built page, internal links resolve, no page names the private site's address; wire them into `npm test` in `site/` and verify they pass

## 4. API reference (app/worker/apps/relay/)

- [x] 4.1 Write `api-doc.ts` rendering the reference from the relay routes via `registrations()` and `schemas()`, and the `relay:api-doc` script in `app/package.json` that writes `site/src/content/docs/api/reference.md`
- [x] 4.2 Write `api-doc.test.ts`: the committed page equals `apiReference()`, a described action renders its fields, errors and example, and a bare handler renders as a link; verify `npm test` in `app/` passes with full coverage

## 5. Publish step and guard (scripts/)

- [x] 5.1 Write `scripts/publish-relay-site.mjs` (export at `--ref`, `npm ci`, test, build, guard, deploy; `--staging`, `--dry-run`; one `result=` line), reusing `blocked()` and adding `siteBlocked()` for email addresses, Access team domains, the main Worker's addresses and Access IDs from `app/wrangler.jsonc`
- [x] 5.2 Write `scripts/publish-relay-site.test.mjs`: each refused kind names the file and never the value, a clean `dist/` passes, `result=empty` with no `site/`; verify with `node --test scripts/publish-relay-site.test.mjs`
- [x] 5.3 Add the site rules to `AGENTS.md`'s Relay section (run after each publish beside the app copy, report both lines, never weaken the guard, each Relay change updates its page), and write `wiki/relay-website.md` linked from `wiki/README.md`

## 6. Verification

- [x] 6.1 Run `npm test` in `site/`, `node --test scripts/publish-relay-site.test.mjs scripts/publish-relay-app.test.mjs`, and `node scripts/publish-relay-site.mjs --dry-run` on an unsaved snapshot of the tree; all pass and the dry run prints `result=ready` (the app's full `npm test` is judged by the check run in 6.4)
- [x] 6.2 Preview with `node scripts/publish-relay-site.mjs --ref HEAD --staging`; open `relay-staging.matthewwong525.workers.dev` at 390 and 1280 px, and pass each picture with the approved card to `preview-review.mjs --approved`; check search, dark mode and the phone menu
- [x] 6.3 Confirm the private site still asks for its login, and that the preview's files hold no private address or key (the guard's report)
- [x] 6.4 `/save` the change and read its check run, including the API reference test

## 7. Data-first home page

- [x] 7.1 Rewrite the hero, cards, flow and menu order for Relay as a way to get your own data into a place you choose, with the ring as one way to take notes; rewrite *Connections* (database webhooks, MCP, example skill and tables, all coming; no memory-platform words); update the prototype and the spec's home page requirement
- [x] 7.2 Run `npm test` in `site/` and the guard, preview at relay-staging, and show Matthew the plan link and the preview before publish

After publish, by the Relay rule in `AGENTS.md` (not a task, because a task can't wait for its own publish): run `node scripts/publish-relay-site.mjs`, report `result=deployed url=https://relayeverything.com`, and open it with no login.
