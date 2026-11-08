# Tasks

## 1. The inbox (server)

- [x] 1.1 Add the D1 migration with `relay_inbox_links` and `relay_inbox_held`, and `schema/space-migrations/0007_inbox.sql`, which widens `relay_devices.reaches` with `inbox` (copy, drop, make again, `defer_foreign_keys`). `space-schema.test.ts` shows a new space and a space at `0006` both have it.
- [x] 1.2 Add `inbox/links.ts`: HMAC of an address or sender, make and replace a person's address, find a person by address or by checked sign-in email, and `vouch("inbox", …)`. Add it to the allowed files in `space-access.test.ts`. Tests: a new address, a replaced address no longer found, a sign-in email found, an unknown email not found.
- [x] 1.3 Add `inbox/receive.ts`: the `InboxItem` type, the *Email* `inbox` device made on first use, files sealed through `attachments.ts` within the note file limits, and `addNote` with `clientId = "email:<id>"`. Tests: words only, files, a file over the limit left out and named, an eleventh file left out, a repeat stores once, and `isolation.test.ts` shows Ana's address never reaches Ben's space.
- [x] 1.4 Add `inbox/held.ts`: keep mail from an email with no account, sealed by HKDF from the email (100 messages and 50 MB each, oldest dropped), and claim at each sign-in while kept mail waits for the email (in time order, files sealed again with the space key, held rows and objects deleted). Add a daily Cron Trigger to `wrangler.relay.jsonc` and a `scheduled()` handler in `worker/relay-only.ts` that deletes held rows and objects older than 30 days. Tests: keep then claim with first times, a claim run twice stores once, the cap drops the oldest, the database rows alone can't be opened, the sweep deletes only old rows.
- [x] 1.5 Add `inbox/email.ts` with `postal-mime` and the `email()` handler in `worker/relay-only.ts`: a secret address (any sender), `notes@` (by `From`, only with the `Authentication-Results` pass; kept when the email has no account), any other address rejected, subject and plain words cut at the reply quote, HTML turned to text when there is no plain part, and attachments. Tests with saved `.eml` files: forwarded with a PDF, any sender to a secret address, `notes@` from a sign-in email, `notes@` from a new email kept and claimed at sign-up, `notes@` failing DMARC dropped, an old address dropped, email off drops all. No mail is ever sent.
- [x] 1.6 Add `GET /apps/relay/api/inbox` and `POST /apps/relay/api/inbox/address` (a new address), both for the signed-in person only. Document `RELAY_INBOX_HMAC_KEY` and `RELAY_INBOX_MAIL_DOMAIN` in `app/.dev.vars.example` and `.env.example`. Route tests, with a device key refused. Run `npm run relay:api-doc`.
- [x] 1.7 Show a note's channel in the web API, the AI connector and `note.created` through its device name, and add *Email* to the kinds list in `kinds.ts` if it lists ways in. Regenerate `site/public/webhooks/v1.schema.json` only if the shape changes. `format.test.ts` and the connector tests cover an emailed note.

## 2. The page card

- [x] 2.1 Add `app/src/apps/relay/Inbox.tsx`, the *Email* card from the proposal's sketch: the address, *Copy*, *New address* behind a confirm, the shared address line and the warning; no card when email is off. Component tests for each state and for a new address, and `App.test.tsx` lists the new request.

## 3. Website and wiki

- [x] 3.1 Write `site/src/content/docs/app/email.md` (*Email notes*: find and replace the address, the shared address, what a note keeps, the file limits, mail kept 30 days before sign-up, the warning, `<your-relay-server>`). Add it to the docs sidebar and to `scripts/product-name.test.mjs`. Update `privacy.md` (what Cloudflare sees on the way, the address HMAC, and mail kept sealed for 30 days from emails not yet signed up) and `start/run-your-own.md` (the optional mail domain and Email Routing steps).
- [x] 3.2 Add a *Ways in* section to `wiki/relay-spaces.md`: the inbox lookup before a space opens, the HMAC and why, kept mail and its sweep, the `inbox` device, the Email Routing steps for a subdomain (MX records and a catch-all rule to the Worker through the API, since the token can't change the zone's routing settings), and that staging has its own mail subdomain.

## 4. Checks and turning email on

- [x] 4.1 Run `npm test` in `app/`, the website tests, `node scripts/public-check.mjs` and `node scripts/product-name.test.mjs`. All pass.
- [x] 4.2 Set up staging: Email Routing for `in-staging.relayeverything.com` to the staging server, and the secrets. Deploy the staging spaces Worker and server by hand ([the Workers and their order](../../../wiki/relay-spaces.md#the-workers-and-their-order)).
- [ ] 4.3 `/save`, then on `app-staging.relayeverything.com`: copy the card's address, email a PDF to it from any account, and see the note with the PDF. Write to `notes@in-staging.` from the sign-in email and see the note. Replace the address and see mail to the old one make no note.
- [ ] 4.4 Preview the website with `node scripts/publish-relay-site.mjs --ref HEAD --staging` and check the new page.
- [ ] 4.5 After the publish, set Email Routing for `in.relayeverything.com` and the live secrets, then send one mail to a secret address and one to `notes@`, and see both notes.
