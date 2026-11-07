# Design

## Context

`site/src/content/docs/privacy.md` already explains, in plain words, what is kept where and how to turn each part off; it is in the menu (`site/sidebar.mjs`, *About*). There is no terms page. The site guard in `scripts/publish-relay-site.mjs` refuses any email address in `site/`, so the contact address cannot live on the website. The shared server (`app/wrangler.relay.jsonc`, `worker/relay-only.ts`) answers `GET /apps/relay/sign-in/methods` with no sign-in, and `SignIn.tsx` already reads it. The same server code runs on self-hosts, so nothing owner-specific may be fixed in code.

Data handlers today: Cloudflare (Workers, Durable Objects, D1, R2, Queues, Email Service for sign-in codes; Workers logs are off, no `observability` key), Apple and Google (Sign in with Apple and Google, the phone's address lookup, HealthKit and Health Connect on the phone), Hugging Face (the one speech model download), and, only when the person sends it, the AI apps they connect (Anthropic, OpenAI) and their webhooks.

## Goals / Non-Goals

**Goals:** real draft text a lawyer can read and edit; one deterministic check for gaps; a contact address that self-hosts don't inherit.

**Non-Goals:** legal advice or a final text; region-by-region carve-outs (the rights apply to everyone); payments or texting terms.

## Decisions

- **Three pages, beside `privacy.md`**: `terms-draft.md`, `privacy-policy.md`, `health-privacy.md` at the docs root. The live `terms.md`, with its *Texting terms* part, and `privacy.md`'s `## Texting` part belong to texting-toll-free-pages; this change does not touch them. `terms-draft.md` copies the *Texting terms* part word for word, so it can replace `terms.md` at `/terms/` when the company forms, and the carrier-words test in `site.test.mjs` must pass on it too. `privacy.md` stays the plain guide and owns the *what is kept where* table; the policy links to `../privacy/#what-is-kept-and-where` instead of copying it, so the two cannot drift. Alternative: turn `privacy.md` into the policy. Rejected: the legal sections would bury the plain guide people read today.
- **Draft box**: a Starlight `:::caution[Draft: not in force]` aside as the first block of each page. Alternative: Starlight `draft: true`. Rejected: drafts are left out of the production build, so the staging preview and a lawyer could not read them.
- **The gap check** goes in `site/tests/site.test.mjs`, reading the Markdown sources: every page whose slug is in the sidebar, or is linked from `index.mdx`, must not contain `[LEGAL-TODO`; every page that contains it must open with the draft aside. Source files, not built HTML, so the message names the file a person edits.
- **Gaps**: company legal name, a postal address, and the start date. Ontario's law applies to the terms. The privacy policy follows PIPEDA (consent, a person in charge of privacy, access and correction, a complaint to the Office of the Privacy Commissioner of Canada) and names Quebec's Law 25 for Quebec users. All written `[LEGAL-TODO: <what>]`.
- **Contact**: a new optional var `RELAY_CONTACT_EMAIL`. `methods` in `sign-in/email.ts` adds `contact` only when it is set. `SignIn.tsx` shows a `mailto:` line under the buttons; `Account.tsx` shows the same line. Live and staging in `wrangler.relay.jsonc` set `privacy@relayeverything.com`; `self-host/wrangler.jsonc` leaves it unset, and `start/run-your-own.md` names the setting. The pages say *write to the contact address on the shared server's sign-in page, https://app.relayeverything.com*; that host is public, and the guard refuses only the company app's hosts.
- **Mail forward**: Cloudflare Email Routing rule `privacy@relayeverything.com` → the owner's verified inbox, through the API with `CLOUDFLARE_API_TOKEN` if its scope allows, else the dashboard steps. Outward: the build asks before it adds the rule.
- **Retention text**: data is deleted from the person's space when they delete their account; the policy says Cloudflare's recovery copies of Durable Object storage can hold it for up to 30 days more. The build confirms that figure in Cloudflare's docs and cites it on the page.

## Risks / Trade-offs

- [The drafts are public before they are in force] → the draft box says so on each page, and they are in no menu.
- [AI-written legal text can be wrong] → the release flow puts a lawyer's read before the pages go live; this change does not make them live.
- [A spam bot finds the address on the sign-in page] → it is a forward, so it can change or stop at any time with no code change.

## Migration Plan

Publish as usual; then run `node scripts/publish-relay-site.mjs` and deploy the shared server so `methods` returns `contact`. Rollback: remove the var; the line goes away.
