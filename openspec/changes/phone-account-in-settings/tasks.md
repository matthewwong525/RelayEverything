# Tasks

## 1. Server

- [x] 1.1 `app/worker/apps/relay/connections.ts`: add `email` (from `caller.email`) to the output schema and answer; describe it. Test in `connections.test.ts`: a phone key gets its own person's email and no other person's.
- [x] 1.2 Run `npm run relay:api-doc` in `app/`.

## 2. Phone: Settings and the Account page

- [x] 2.1 `relay.dart` / `controller.dart`: `Connections` gains an optional `email`; old saved values still decode.
- [x] 2.2 `settings.dart`: `_AccountRow` first, in its three states (signed in, own webhook, signed out); the signed-out tap runs `choosePlace`, the others open the Account page.
- [x] 2.3 New `account.dart`: `AccountPage` from `SendingPage` with the email and server, *AI apps* and *Webhooks* (moved from `home.dart`), *Open your Relay Everything page*, *Server*, and *Sign out* (today's disconnect, with its confirm); in webhook mode, the address, *Send a test*, *Notes from elsewhere* and *Stop sending*. Remove `SendingPage` from `folder.dart`.
- [x] 2.4 `home.dart`: remove the *Connections* section and `_connected`; keep `refreshConnections` on open.
- [x] 2.5 `connect.dart`: one *Sign in* screen with *Sign in to connect* primary and *Scan a key*, *Use another server*, *Send to my own webhook instead* below; the kept-key line stays. Its key line stops saying the key *can send but not read*: since note sync (#64) and delete (#69), a phone key reads and changes its person's notes.
- [x] 2.6 `folder.dart`: the folder pages say they work once you sign in, and the button reads *Sign in*.
- [x] 2.7 Widget and controller tests (leave the note's ⋯ *Delete* and swipe-to-delete from #69 as they are): Home has no *Connections*; Settings' first row in each of the three states; signed-out tap opens sign-in and asks nothing of the network; Account page lists names and opens `#ai-apps` / `#webhooks`; *Sign out* confirms, forgets the key, stops sending and keeps this phone's notes; webhook mode shows *Stop sending* and keeps the webhook; a folder's *Sign in* opens sign-in. Update the tests that tapped Home's *Sending*.

## 3. iPhone check and docs

- [x] 3.1 The fixed tour, after #68: `mobile/device-check/flows/settings.yaml`, which `tour.sh` runs and which gates a release, stops tapping Home's *Sending*. It asserts Settings shows *Sign in to Relay Everything*, taps it, waits for the *Sign in* screen, and takes the `settings` and `sign-in` screenshots. Check `tour-json.mjs` still lists the flows.
- [x] 3.2 `AGENTS.md` (and its `CLAUDE.md` copy) *Device keys*: a phone key also reads its own account's email. `mobile/README.md`: Home, Settings, the Account page and sign-in.
- [x] 3.3 Website: `site/src/content/docs/app/settings.md`, `app/your-notes.md`, `start/connect-a-phone.md`, `connections/index.md`, `api/keys.md` say the Account row, *Sign in* and *Sign out*.

## 4. Checks

- [x] 4.1 `flutter analyze` and `flutter test` in `mobile/`; `npm test` in `app/`; `node scripts/product-name.test.mjs`; `node scripts/public-check.mjs`.
- [ ] 4.2 `/save`, then the iPhone device check (`scripts/device-check.mjs run`, with a scenarios file in a temporary folder) on the saved commit: the tour passes, and Claude's steps through `flow.sh` show Home with no *Connections*, Settings' Account row signed out, the *Sign in* screen, and *Delete* still in a note's ⋯ menu.

## 5. Review fixes

- [x] 5.1 `mobile/device-check/flows/timeline.yaml`: drop the check for Home's *AI apps · Sign in to see* row, which this change removes, and check that *Connections* is not on Home, so the fixed tour still passes.
- [x] 5.2 `mobile/test/controller_test.dart`: *Stop sending* in webhook mode keeps the webhook's address and secret after a restart, and sending there again works.
