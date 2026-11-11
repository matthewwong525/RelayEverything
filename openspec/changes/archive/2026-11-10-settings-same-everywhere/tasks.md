# Tasks

## 1. Start on top of the plugin change

- [x] 1.1 Confirm agent-plugin-and-mcp-address is merged on `main` and this branch contains it; read its `HomeScreen.otherConnections`, `screens/transcripts.dart` and the web left bar, and verify `flutter analyze` in `mobile/` passes before any edit.

## 2. Server: what a phone reads, and signing out one phone

- [x] 2.1 Add `devices` (phones and computers: id, name, kind, since, last chat), `notesAddress`, `sharedAddress` and each AI app's `connectedAt` to `GET connections` in `app/worker/apps/relay/connections.ts`; add tests that a phone key gets them from its own space only, with no `api` row and no key, and that a chat key and an API key are refused.
- [x] 2.2 Let a phone key call `POST devices/off` in `app/worker/apps/relay/device.ts` for a phone of its own space only; add tests that it signs out another phone, is refused for a computer, an API key and another person's phone, and that the session still signs out any device.
- [x] 2.3 Add a test that a phone key is refused on `POST ai-apps-disconnect`, `POST inbox/address` and `POST devices`.
- [x] 2.4 Make *Add a device* on the web make only an API key, with no QR code; run `npm run relay:api-doc` in `app/`; update the *Device keys* and *offline by default* lines in `AGENTS.md` (a phone key also reads device names, both notes addresses and AI apps' connect days, and signs out one of its person's phones; *Add a device* becomes *Add an API key*; the sign-in has no *Send to my own webhook instead*).

## 3. Shared screens: Settings, Account, Webhooks

- [x] 3.1 Add the one list of Settings rows with a phone-only flag, and build the phone's `SettingsScreen` and the web's `SettingsView` from it; add a widget test for the phone's order (account, Appearance, Notes, Voice notes, version) and the web's (Account, Appearance).
- [x] 3.2 Make the account card say only *Signed in* when signed in, and keep the webhook and signed-out states; add widget tests for each state.
- [x] 3.3 Rebuild Account on both shells: the card with *Sign out*, *Phones* (*This phone*, *Sign out* with a confirm on each other phone), *Advanced* (Webhooks; on the web API keys), and *Delete my account* (the phone opens the page); keep the no-account webhook page; add widget tests for signed in, signing out another phone, cancel, and webhook.
- [x] 3.4 Add the phone's `WebhooksPage`: the muted line, names, the link to the page, and the *Only to my own webhook* switch (signed in only); on the web, *API keys* (`devices_page.dart` for `api` rows, *Add an API key*) and the existing Webhooks page; add widget tests that the switch with no webhook opens the setup, leaving it unsaved changes nothing, and turning it off sends waiting private data to Relay Everything.
- [x] 3.5 Give `quietButton` in `lib/brand.dart` the app's font (`fontFamily: brandFont`); add a golden test of *Copy* and *Sign out* with the real fonts that shows their words.
- [x] 3.6 Map the old `#parts` (`account`, `devices`, `webhooks`, `appearance`, `ai-apps`, `chats`, `email-notes`) to their new places; add a test for each.

## 4. Shared screens: Other connections

- [x] 4.1 Add *Connect your AI*: *Claude Code and Codex* (computers with their last saved chat, *Saved chats* opening the saved chats, *Get the plugin*) and *Claude, ChatGPT and other AI apps* (the address with *Copy*, apps with their connect day); the web keeps *Disconnect*, the phone opens the page, and signed out shows *Sign in* with no request; add widget tests on both shells.
- [x] 4.2 Add *Email notes*: what it does, then the shared address (only from the sign-in email) and the private address (from anyone), each with *Copy*; the web keeps *New address*; add widget tests on both shells, and that signed out makes no request.
- [x] 4.3 Put both rows, each with its one line, under *Other connections* on the phone's Home and in the web's left bar; remove the *AI chat transcripts* row from both, and the web's `ai_apps_page.dart` and `email_notes_page.dart` once folded in; add Home and left-bar widget tests.

## 5. Sign in and the webhook setup

- [x] 5.1 Make the sign-in one *Sign in* button and the quiet link *Don't want an account? Use your own webhook*; remove scan, paste and the server field, keep a saved server working, and keep the kept-key and `signInOnly`/`privateOnly` modes; add widget tests that the sign-in shows only those two controls and that the no-account path saves and sends to the webhook.
- [x] 5.2 Lay out the webhook setup as four numbered steps (address, copy secret, send a test, Save) with no change to its checks; keep the `http://` refusal and test-message widget tests passing.

## 6. Website, self-host guide and device check

- [x] 6.1 Update `site/src/content/docs/app/settings.md`, `start/connect-a-phone.md`, `start/sign-up.md`, `start/run-your-own.md`, `api/keys.md`, `api/connect-a-service.md`, `app/on-a-computer.md`, `app/email.md`, `connections/your-database.md`, `privacy.md` and `app/self-host/SETUP.md` for the new places, *Add an API key*, and no *Scan a key* or *Use another server* on the phone; check with `grep` that none of the old labels stay in `site/`, `app/self-host/` and `mobile/README.md`.
- [x] 6.2 Update `mobile/device-check/flows/` where a flow taps an old label; check that the flows name only labels that exist in the screens.

## 7. Checks

- [x] 7.1 Run `flutter analyze` and `flutter test` in `mobile/`, `npm test` in `app/`, `node scripts/product-name.test.mjs` and `node scripts/public-check.mjs`; verify all pass.
- [x] 7.2 After implementation, run `/save`; check the web app on staging (`node scripts/publish-relay-server.mjs --ref HEAD --staging-only`) in headless Chromium: Settings lists Account and Appearance; Account has Phones and Advanced; *Connect your AI* and *Email notes* open in the main pane; `/#webhooks` opens Webhooks and `/#chats` opens Connect your AI. Verify the iPhone device check passes on the pull request.

## 8. Review fixes

- [x] 8.1 Fix the review notes: the *Connect this computer?* page and the plugin (`plugin/README.md`, `plugin/bin/connect.mjs` and its test) say to disconnect a computer in *Connect your AI*, not *Devices*; the phone's *Email notes* says the server takes no email only when the answer carries the address keys, with a widget test for a copy kept by an older app or server; move the `daysAgo` comment back and fix comments that name gone labels; delete the unused `site/src/assets/web/settings-computer.png`. Run `flutter analyze` and `flutter test` in `mobile/`, the plugin's tests, and the local checks.
