# Tasks

Before you start: if `flutter-web-app` is on `main`, skip group 4. If `landing-page-refresh` is on `main`, `site/src/content/docs/index.mdx` is gone: in 1.1 add `site/src/pages` to `PLACES` and read `.astro` as markup, and in 2.3 edit only what remains (design.md, *Whichever publishes second catches up*).

## 1. The ring check

- [x] 1.1 In `scripts/product-name.test.mjs`, add `ringWords(path, text)` beside `bareNames`: it reads through `readable()` and refuses `/\bring\b/i` unless the word is inside quotes or a backtick or follows a hyphen; add a `test()` that runs it over `userFacingFiles()` minus `wiki/` and fails with each `path:line: text`. Verify: unit cases in the same file pass for `The Relay Everything ring` (refused), `'ring'`, `"ring"`, `` `ring` ``, `relay-ring`, `focus-visible:ring-[3px]` and `HoldRingPainter` (passed).

## 2. The website

- [x] 2.1 Delete `site/src/content/docs/ring/` and `site/src/assets/ring/`, and the *The ring* entry in `site/sidebar.mjs`. Verify: `cd site && npm test` passes, and no built page links under `/ring/`.
- [x] 2.2 Add `site/public/_redirects` with `/ring/* / 301`. Verify: the file is in `site/dist/` after `npm run build`.
- [x] 2.3 Edit the ring text out of `index.mdx` (the card line, the *A ring to take notes* section, *the ring's models and board*), `start/what-you-need.md` (description, intro, table row, note), `privacy.md` (the row becomes *Older recorded notes*, *No longer sent*), `app/your-notes.md` (description, line 125, the page section, remove *Where a ring note's place comes from*, *amber circle*), `app/voice-notes.md` (*amber circle* twice, remove the ring rule line), `app/photos.md`, `app/settings.md`, `api/keys.md`, `api/recordings.md` (*an older recorded note*), `connections/your-database.md` (*older recorded note*), and the `connections/claude-code.md` example (a non-ring project and chat). Verify: `node --test scripts/product-name.test.mjs` reports no hit under `site/src/content`.

## 3. The server's words and the generated API pages

- [x] 3.1 In `app/worker/relay-mcp/`: `tools.ts` instructions say *notes from their phone*; `inputs.ts` says *Only older recorded notes, or only typed ones.*; `api.ts` says `source` picks *older recorded or typed notes*; `answers.ts` titles an empty note *A recorded note with no words*, and `tools.test.ts:241` expects it. In `app/worker/apps/relay/webhooks/format.ts`, the three descriptions say *an older recorded note*. Verify: `cd app && npx vitest run worker/relay-mcp worker/apps/relay/webhooks` passes.
- [x] 3.2 Run `npm run relay:api-doc` in `app/`, and read the diff of `site/public/api/v1.openapi.json`, `site/public/webhooks/v1.schema.json` and `site/src/content/docs/api/v1-reference.md`: only the descriptions move. Verify: the ring check reports no hit under `site/public`.

## 4. The web page (skip if `app/src/apps/relay/` is gone)

- [x] 4.1 `Notes.tsx`: drop the *Ring* / *Typed* badge, set the card's `aria-label` to `Note`, and the empty text to *No notes yet. Write one in the Relay Everything app.*; `Photos.tsx`: *Recordings, notes, health and places stay.*; `app.json`: *Your notes, today's health and the places you've been.* Update `App.test.tsx` (lines 106 and 164 find a note by `Note`) and `Photos.test.tsx:72`. Verify: `cd app && npx vitest run src/apps/relay` passes.

## 5. The phone app

- [x] 5.1 `mobile/lib/screens/account.dart`: the subtitle says *The notes from all your devices, with their recordings.*; `mobile/ios/Runner/Info.plist`: the *Always* location text ends *to make your stays and trips.*; `mobile/README.md`: *amber circle*, and drop the sentence on a ring note taking the nearest point; `mobile/lib/voice/transcriber.dart`: drop the comment line that promises a ring. Verify: `cd mobile && flutter analyze && flutter test` pass, and the ring check reports no hit under `mobile/`.

## 6. The wiki and project rules

- [x] 6.1 `wiki/relay-website.md`: drop *Do not describe it as a smart ring first…* and the ring pictures paragraph, and add that public text names no ring, with the check; `wiki/brand.md`: drop *The ring circle is not the logo*; `wiki/open-source.md`: drop the sentence on the ring's board and models; `AGENTS.md`: *app, server or connections*. Verify: `memory.mjs areas wiki/relay-website.md` shows no broken link, and the wiki link check passes.

## 7. Checks

- [x] 7.1 Run `node --test scripts/product-name.test.mjs`, `(cd app && npm test)`, `(cd site && npm test)`, `(cd mobile && flutter analyze && flutter test)` and `node scripts/public-check.mjs`. Verify: all pass.
- [ ] 7.2 Run `/save`, then `node scripts/publish-relay-site.mjs --ref HEAD --staging`. Verify on relay-staging.matthewwong525.workers.dev: the docs menu has no *The ring*, `/ring/board/` opens the home page, and a search for *ring* finds only the `source` value `ring`, with no page about the ring device.
