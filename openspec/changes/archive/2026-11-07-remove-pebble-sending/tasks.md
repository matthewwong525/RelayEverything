# Tasks

## 1. Server

- [x] 1.1 Delete `app/worker/apps/relay/pebble.ts`, `signature.ts`, `pebble.test.ts` and `signature.test.ts`; drop `POST pebble` from `api.ts`. Add an `api.test.ts` case: a live phone key posting to `/apps/relay/api/pebble` gets 404 from the router and stores no note; `device.test.ts` checks the gate refuses it first with 403, as any address a phone key does not reach.
- [x] 1.2 Take `pebble` out of the phone routes in `caller.ts`; in `api-doc.ts` remove the `HAND_PAGES` entry and say "a phone key" for phone routes. Update `api-doc.test.ts` to match.
- [x] 1.3 In `device.ts`, stop making and storing a Pebble secret, drop `pebbleSecret` from the answer, and rewrite the `reaches` and route descriptions without Pebble. `device.test.ts` checks the answer has no `pebbleSecret` and no `relay_device_secrets` write.
- [x] 1.4 Add `schema/space-migrations/0005_no_pebble.sql`: drop `relay_device_secrets` and the `relay_outbox_note_updated` trigger. `space-schema.test.ts` checks both are gone, on a fresh space and on a space that held secret rows.
- [x] 1.5 Delete `place.ts` and the location batch's call to it in `samples.ts`; fix the `locations` description. Change the `note.updated` description in `webhooks/format.ts` to say the server no longer sends it, and the `device` description to "The phone or other device that sent the item." Keep `send.ts` sending a `note.updated` row already in an outbox.
- [x] 1.6 Update the webhook tests: `migration.test.ts` and `send.test.ts` check a location batch near a ring note with no place changes nothing and logs no `note.updated`; keep one `send.test.ts` case that sends a `note.updated` row already waiting. Fix `format.test.ts` and `receiver.test.ts` for the new descriptions.
- [x] 1.7 Rename the Pebble fixture in `app/tests/relay.ts` and `app/tests/relay-space-rows.sql` to a second phone (*iPad*), with no `relay_device_secrets` insert; keep the seed ring notes. Update every test that names the Pebble key (`api`, `attachments`, `chats`, `isolation`, `queries`, `sign-in/phone`, `keys`, `relay-mcp/tools`) and confirm `git grep -i pebble app/worker app/tests` finds nothing.
- [x] 1.8 In `scripts/relay-forward/`, change the comment in `worker.mjs` and send the test's example to `/apps/relay/api/notes` with a plain header; `node --test scripts/relay-forward/worker.test.mjs` passes.

## 2. Web app

- [x] 2.1 Remove the `pebble` kind from `app/src/apps/relay/Devices.tsx` and `PebbleSteps` and `pebbleSecret` from `Setup.tsx`; reword the empty list line and file comments. Update `App.test.tsx` and `SignIn.test.tsx`: *Add a device* offers Phone, Claude Code and API key only.

## 3. Phone app

- [x] 3.1 Take the Pebble sentence out of the *Send to Relay Everything* line in `mobile/lib/screens/settings.dart`, keeping the rest of the wording (or the newer wording from `phone-sends-to-your-webhook` if it is live). The Flutter tests pass.

## 4. Website and docs

- [x] 4.1 Delete `site/src/content/docs/start/pebble-webhook.md` and `api/pebble-webhook.md`, and their entries in `site/sidebar.mjs`.
- [x] 4.2 Remove or reword every Pebble mention in `site/src/content/docs/`: `api/keys.md`, `start/what-you-need.md`, `start/connect-a-phone.md`, `start/run-your-own.md`, `start/sign-up.md`, `app/settings.md`, `app/your-notes.md` (ring notes keep a stored place; none is added later), `connections/your-database.md` (`note.updated` no longer sent; example device not *Pebble app*), `ring/how-it-works.md` (the Relay Everything ring will send through the phone app), `privacy.md` and `index.mdx`. `git grep -i pebble site/src` finds only the ring's size comparison, if any.
- [x] 4.3 Run `npm run relay:api-doc` in `app/`; `api/reference.md` and `site/public/webhooks/v1.schema.json` have no Pebble route, `pebbleSecret` or "Pebble key".
- [x] 4.4 Update `AGENTS.md` (device keys line), `README.md`, `self-host/SETUP.md` step 6, `wiki/relay-website.md` (the `HAND_PAGES` example) and `wiki/relay-spaces.md` (the secret table now dropped by `0005`). `node scripts/product-name.test.mjs` passes.
- [x] 4.5 Preview the website with `node scripts/publish-relay-site.mjs --ref HEAD --staging` and check the sidebar has no Pebble page and the ring page reads right.

## 5. Checks

- [x] 5.1 Run `npm test` in `app/` and `node scripts/public-check.mjs`; both pass.
- [x] 5.2 `/save`, then on the preview: *Add a device* shows no *Pebble app*, a new phone key shows no signing secret, the timeline still shows the seed ring notes as *Ring* with their places, and `POST /apps/relay/api/pebble` with a phone key answers 403 (*A device key can only send to Relay Everything.*), as any address a phone key does not reach.
