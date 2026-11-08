# Tasks

## 1. The legal pages

- [x] 1.1 Bring in main, or the texting-toll-free-pages branch if it has not published, so the live `terms.md` and its tests are here. Write `site/src/content/docs/terms-draft.md` (with the live page's *Texting terms* part, word for word), `privacy-policy.md` and `health-privacy.md` by the design: each opens with the *Draft: not in force* aside, each gap is `[LEGAL-TODO: …]`, the policy links to the *Privacy* table and copies none of it, and each Cloudflare, Apple, Google and Hugging Face line cites that service's own page. Confirm the Durable Object recovery window in Cloudflare's docs and cite it. Check: `npm test` in `site/` passes, and each page opens at its address in the built site.
- [x] 1.2 Add the gap check to `site/tests/site.test.mjs`: no `[LEGAL-TODO` on a menu page or a page linked from the home page, and a draft aside on every page that holds one. Check: the test passes, fails when `privacy.md` gets a gap for a moment, fails when the aside is taken off `terms-draft.md` for a moment, and the carrier-words test still passes.

## 2. The contact line

- [x] 2.1 Add optional `RELAY_CONTACT_EMAIL` to `SignInEnv`; `methods` returns `contact` only when it is set. Set it to `privacy@relayeverything.com` on live and staging in `app/wrangler.relay.jsonc`. Test in `sign-in/email.test.ts`: with the var, `contact` is the address; without it, there is no `contact` key.
- [x] 2.2 Show *Questions or privacy requests:* with a `mailto:` link in `SignIn.tsx` under the buttons and in `Account.tsx`, only when `contact` is present. Tests in `SignIn.test.tsx` and the account test: the line shows with `contact` and is absent without it.
- [x] 2.3 Update `site/src/content/docs/start/sign-up.md` (where to reach us) and `start/run-your-own.md` and `self-host/SETUP.md` (the optional setting), and run `npm run relay:api-doc` in `app/` if `methods` is in the route list. Check: `npm test` in `site/` and `node scripts/product-name.test.mjs` pass.

## 3. The mail forward

- [x] 3.1 Add the Email Routing rule `privacy@relayeverything.com` → matthewwong525@gmail.com (the person said yes) (API if the token's scope allows, else give the dashboard steps). Check: a test mail to the address arrives.

## 4. Checks

- [x] 4.1 Run `npm test` in `app/` and `site/`, `node scripts/public-check.mjs`, and `node scripts/publish-relay-site.mjs --ref HEAD --dry-run`; each passes, and the guard prints `result=ready`.
- [x] 4.2 After `/save`, preview with `node scripts/publish-relay-site.mjs --ref HEAD --staging`: the three draft pages open at relay-staging with their draft box and are not in the menu, and the live `/terms/` is unchanged; app-staging.relayeverything.com's sign-in screen shows the contact line.
