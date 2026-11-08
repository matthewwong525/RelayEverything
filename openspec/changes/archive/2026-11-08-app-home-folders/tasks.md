# Tasks

## 1. Server: the phone key reads connection names

- [x] 1.1 Add `GET /apps/relay/api/connections` in `app/worker/apps/relay/connections.ts` and one entry in `api.ts`'s route list: AI app names from the connector's grant list (empty when it is not set up) and webhook names from `relay_webhooks`, from the caller's own space; verify with a test that the answer holds names only, no address, secret, kinds or send state.
- [x] 1.2 Let a `phone` key reach that one `GET` path in `caller.ts`'s `reaches()`, and no other key; verify with tests in `caller`/`isolation` that a phone key passes, a chat key and an API key are refused, and a phone key still can not read the timeline.
- [x] 1.3 Give the AI apps and webhooks cards on the Relay Everything page the ids `ai-apps` and `webhooks`; verify in `AiCard.test.tsx` and `Webhooks.test.tsx`.
- [x] 1.4 Run `npm run relay:api-doc` in `app/` and verify `api-doc.test.ts` passes with the new route.

## 2. Phone app: Home and the folders

- [x] 2.1 Add `NotesFolder` (all, voice, shares) and `entryIn(folder, entry)`; verify in `days_test.dart` or a new test that a note with a photo, a file or a link is a share and a typed note with none is not.
- [x] 2.2 Add `GET connections` to the sender, keep the last answer in `state`, call it after each sync and when Home opens only while sending to a Relay Everything server, and clear it when sending turns off or the phone disconnects; verify in `sync_test.dart` and `offline_test.dart` that no request leaves with sending off or on a webhook.
- [x] 2.3 Build `screens/home.dart`: the large *Home* title and sync line, the ⋯ menu, the notes card with counts, the *On this phone* and *Connections* cards with folding headers remembered on the phone, search across every folder, and the dock; move the notices, the listening overlay and the Shortcuts voice stream here from the timeline; make it `RelayApp.home`. Verify in `screens_test.dart`: the first open, counts, folding, search, the menu with sending off and on, and a Shortcuts voice note started while a folder page is open.
- [x] 2.4 Build `screens/folder.dart` with the Location, Health, Calendar and Sending pages from the rows in `settings.dart`, the one-line status for each Home row, and *Turn on sending* with sending off; verify in `screens_test.dart` each row's line, each switch acting as before, and *Turn on sending* opening the choice of place.
- [x] 2.5 Make the *AI apps* and *Webhooks* rows show the kept names, or *Sign in to see* and open the choice of place, and open `<server>/apps/relay/#ai-apps` or `#webhooks` when signed in; verify in `screens_test.dart` with a fake opener and fake answers.
- [x] 2.6 Let `TimelineScreen` take a folder and a title, show *‹ Home*, drop its ⋯ menu, and search only its folder; rename `BackToNotes` to a back button that takes its label; verify in `screens_test.dart` that *Voice notes* lists only voice notes and *Home* goes back.
- [x] 2.7 Cut `settings.dart` to the *Notes* and *Voice notes* groups; verify in `screens_test.dart` that Settings shows only those two groups, and run `flutter test` in `mobile/` with every test passing.
- [x] 2.8 Update `mobile/device-check/flows/` so each flow starts on Home and taps *Notes* or a folder as needed, and `mobile/README.md` for the new first screen.

## 3. Docs and website

- [x] 3.1 Update the *Device keys* rule in `AGENTS.md` and step 4 of `wiki/relay-spaces.md`: a phone key also reads its person's AI app and webhook names through `GET connections`, and no data; verify `node scripts/product-name.test.mjs` and the wiki checks pass.
- [x] 3.2 Update the website's app pages (`site/src/content/docs/app/your-notes.md`, `settings.md`, `location.md`, `health.md`, `calendar.md`) for Home, the folders and Connections, with no private address; verify `site/tests` pass.

## 4. Checks

- [x] 4.1 Run `/save`, then the iPhone device check on the saved commit with the Home, folder and Connections scenarios, and verify each scenario that the phone can show passes.
