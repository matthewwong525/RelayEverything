# Proposal: Draft the terms, the privacy policy and the health data policy

**Status:** in-progress
**Branch:** incorporate-business-timing
**Open questions:** none

## Why

The public release needs terms of use and a privacy policy: the App Store, Claude's connector directory and the people who sign up all ask for them. Relay Everything keeps health and location data, so it also needs a health data policy, which Washington state law asks for. The company does not exist yet, so the pages start as drafts with marked gaps, and a check stops them going into the menu while a gap is open.

## What Changes

- **Three new draft pages on the website.** Each opens at its own address, so you and a lawyer can read it, but it is not in the menu yet, and a box at the top says *Draft: not in force*. Each gap, such as the company's name, shows as `[LEGAL-TODO: …]`. The short *Terms* page at `/terms/`, which the texting plan makes live for the toll-free check, stays live and in the menu. The fuller terms wait at `/terms-draft/` and replace it, at `/terms/`, when the company forms, keeping its *Texting terms* part.
  | Page | Address | What it says |
  | --- | --- | --- |
  | Fuller terms of use | `/terms-draft/` | Who runs the shared server. You must be 18. Your data stays yours, and we use it only to run the service for you. What you may not do. The service is free, as is, not medical, and not a backup. You can leave at any time. We give 30 days' notice before we shut it down. Limits on what we owe. Ontario's law applies. The code is MIT, and these terms cover only the shared server. The *Texting terms* part, copied from the live page. |
  | Privacy policy | `/privacy-policy/` | Who we are and how to reach us. What we keep: it links to the *Privacy* page's table and does not copy it. Why we keep it: only to run the service for you, with no ads, no sale, no AI training. Who handles it for us: Cloudflare, Apple and Google, Hugging Face. Where it goes only when you send it: your AI apps and your webhooks. How long we keep it, your rights under Canada's privacy law (PIPEDA) and for everyone, children, and changes to the policy. |
  | Health data policy | `/health-privacy/` | The health and location data we keep, why we keep it, who it goes to, how you agree (the app's switch and the phone's permission), how you see or delete it, and Apple's rule that health data is never used for ads. |
- **A check keeps the drafts out of the menu.** A website test fails when a page in the menu, or a page the home page links to, holds a `[LEGAL-TODO` gap. A test also fails when a page with a gap has no *Draft* box. To make the pages live, you fill the gaps, then a small later change removes the boxes, puts the fuller terms in place of `/terms/`, adds the policies to the menu and links them from the home page.
  ```mermaid
  flowchart TD
    D["Draft pages with gaps"] --> C["Form the company"]
    C --> F["Fill the gaps"]
    F --> L["A lawyer reads them"]
    L --> P["Live: the fuller terms replace /terms/"]
  ```
- **The shared server's sign-in page shows a contact address.** Under the sign-in buttons, and on your account card, a line reads *Questions or privacy requests:* with privacy@relayeverything.com. The pages tell people to write to it. A server that you run yourself shows no line until its owner sets an address. The website still shows no email address.
  ```screen
  <div class="card col gap phone">
    <h3>Relay Everything</h3>
    <span class="muted">Sign in or make an account</span>
    <button class="btn-ghost">Continue with Apple</button>
    <button class="btn-ghost">Continue with Google</button>
    <div class="sep"></div>
    <div class="field">Email</div>
    <button class="btn-primary">Send me a code</button>
    <span class="muted">New here? The same steps make your account.</span>
    <span class="muted">Questions or privacy requests: privacy@relayeverything.com</span>
  </div>
  ```
- **Mail to privacy@relayeverything.com goes to your inbox.** A forward in Cloudflare's email settings sends it on.

Non-goals: the company itself, a lawyer's review, the link to the policy inside the phone app (the App Store change adds it), payments terms (payments come later), and texting through Telnyx (the policy gets a line for it when texting ships).

## What the build needs

- **A yes to add the mail forward**: Ready: yes, to matthewwong525@gmail.com. The build adds privacy@relayeverything.com to Cloudflare Email Routing, sent on to your own inbox. Cloudflare sends one check email to that inbox first. If the Cloudflare key can't change email settings, the build gives you the three steps.
- **The company's name and address**: Ready. This build doesn't need them: the pages keep the gaps until you form the company.

## Capabilities

### New Capabilities

- `relay-legal-pages`: the terms, privacy policy and health data policy pages, the draft check, and the contact address on the shared server's sign-in page.

### Modified Capabilities

None.

## Impact

- `site/src/content/docs/`: new `terms-draft.md`, `privacy-policy.md`, `health-privacy.md`. `terms.md` (live) and the `## Texting` part of `privacy.md` come from the change texting-toll-free-pages; this change leaves both as they are.
- Builds on: texting-toll-free-pages (workspace ignorant-badger). Whichever publishes second catches up.
- `site/tests/site.test.mjs`: the draft check, beside that change's carrier-words test, which stays green.
- `app/worker/apps/relay/sign-in/email.ts`: the `methods` answer gets `contact` from a new `RELAY_CONTACT_EMAIL` var; `app/wrangler.relay.jsonc` sets it on live and staging.
- `app/src/apps/relay/SignIn.tsx`, `Account.tsx`: the contact line.
- `site/src/content/docs/start/sign-up.md` and `run-your-own.md`: the contact line, and the setting for a server you run yourself.
- Cloudflare Email Routing on relayeverything.com: one forward (outward).

## Decision log

- **2026-11-07** — Asked where people reach us, since the website refuses any email address → chose a contact line on the shared server's page, with privacy@relayeverything.com sent on to your inbox; the website guard stays as it is.
- **2026-11-07** — Asked whether Claymoo is a registered company → chose no: Relay Everything needs a new company, so the name stays a gap.
- **2026-11-07** — Asked whether you will raise money from investors → chose don't know yet; then, in Canada, a provincial company with a family trust and a holding company was suggested for an accountant to check.
- **2026-11-07** — Asked, after you said you live in Canada, which province → chose Ontario: the terms name Ontario's law, and the privacy policy follows Canada's privacy law (PIPEDA). The Washington health data page stays, for people in the US.
- **2026-11-07** — Asked which inbox the mail forward goes to → chose matthewwong525@gmail.com.
- **2026-11-07** — Assumed: the privacy policy names a person in charge of privacy, because PIPEDA asks for one and Quebec's Law 25 needs it named for Quebec users; until the company forms, it is the owner by role, with the contact address.
- **2026-11-07** — Assumed: the existing *Privacy* page stays the plain guide to what is kept and where, and the policy links to it, because one fact lives on one page.
- **2026-11-07** — Assumed: drafts are built and open at their address with a *Draft* box, not hidden, so the preview and a lawyer can read them.
- **2026-11-07** — Assumed: one gap mark, `[LEGAL-TODO: …]`, for the name, state, address and start date, because one test can then find every gap.
- **2026-11-07** — Assumed: people must be 18 to use the shared server, because it keeps health data; easy to change before release.
- **2026-11-07** — Assumed: a separate health data page, because Washington's My Health My Data Act asks for its own policy, linked from the home page; location counts as health data under it.
- **2026-11-07** — Assumed: the contact address is a server setting, not fixed in the code, because people who run their own server must not send requests to us.
- **2026-11-07** — Note from the chat *PLAN: Toll-free texting pages on the website* (change texting-toll-free-pages): Matthew chose that it makes `/terms/` a short, live Terms page in the menu now, because Telnyx's toll-free check needs terms in force. Applied: the fuller terms stay a draft at `/terms-draft/` until the company forms, then replace `/terms/` in place and keep its *Texting terms* part; only the two policies and the fuller terms are drafts; the carrier-words test stays green; `privacy.md` gets its `## Texting` part from that plan, not this one.
- **2026-11-07** — Assumed: the in-app policy link waits for the App Store change, because that change owns the release steps.
- **2026-11-07** — Assumed: texting-toll-free-pages has not published, and its branch is not pushed, so this branch does not bring it in. `terms-draft.md` copies that change's *Texting terms* part word for word from its worktree, and no other file of it. Whichever change publishes second catches up the other's edits: `site/sidebar.mjs`, `site/tests/site.test.mjs` and `privacy.md`.
- **2026-11-07** — Assumed: the copied *Texting terms* part links to `/texting/` and `/privacy/#texting`, and the draft box links to `/terms/`, which that change adds. `coming` in `site/tests/site.test.mjs` lets a draft page link to those addresses only, and a test fails once they are built, so the list goes at the catch-up.
- **2026-11-07** — Check: `site/tests/site.test.mjs` skips the test that the fuller terms keep the Terms page's *Texting terms* word for word while `terms.md` is not here, because that page comes with texting-toll-free-pages; the test runs once both changes are in.
- **2026-11-07** — Assumed: `self-host/setup.mjs update` keeps `RELAY_SIGN_UP` and `RELAY_CONTACT_EMAIL`, because it wrote each config again from the templates and dropped what the owner set by hand, so the setting the docs name would not last.
- **2026-11-07** — Assumed: the contact line's tests go in `SignIn.test.tsx`, which already holds the account card's tests, and `useMethods` moved to `read.ts` so the account card reads the same answer.
- **2026-11-07** — Assumed: the recovery window is Cloudflare's, cited on the policy: a space (Durable Object) can be restored to any point in the past 30 days, and the account list (D1) to any minute in the past 30 days on Workers Paid, 7 on Workers Free; the policy says *up to 30 days*. R2 keeps no deleted copy by default.
- **2026-11-07** — Assumed: each task's own check ran once at the end, after all source and tests were written, with its acceptance kept.
- **2026-11-07** — Checkpoint inside /ship: built; the review found that the self-host docs promised the contact line on the sign-in screen, which Cloudflare Access hides, so `run-your-own.md` and `self-host/SETUP.md` now say the account card. The mail forward is on, and a test sign-in code sent from app-staging to privacy@relayeverything.com reached matthewwong525@gmail.com. Saved for tasks 4.1 and 4.2.
