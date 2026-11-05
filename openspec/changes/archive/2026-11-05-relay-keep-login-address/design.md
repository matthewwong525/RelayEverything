# Design

## Context

The live Worker `relay-everything` has a custom-domain route (`app.relayeverything.com`) in `app/wrangler.jsonc` and no `workers_dev` key. With routes set, Wrangler defaults `workers_dev` to false and turns the workers.dev subdomain off on each deploy. The live Access app's `domain` is `relay-everything.matthewwong525.workers.dev`, and `scripts/check-private-access.mjs` requires `app.domain` to be that host. Access returns the browser to `app.domain` after the identity step, so the sign-in ends on Cloudflare's 404 page. Staging sets `routes: []`, so its subdomain stays on.

On 2026-11-05 the subdomain was turned on through the API (`POST /workers/scripts/relay-everything/subdomain`, `enabled: true, previews_enabled: false`), and `cloudflared access login` then finished.

## Goals / Non-Goals

**Goals:** a publish never turns the login's return address off, and a config that would is refused before deploy.

**Non-Goals:** previews on the live Worker (`preview_urls` stays off), or changes to the Access app.

## Decisions

- **Set `"workers_dev": true` at the top level of `app/wrangler.jsonc`.** It is inheritable, so staging keeps it too; staging is on today. Alternative: change the Access app's `domain` to `app.relayeverything.com`. Rejected: `checkPrivateAccess` and WongStack setup assume the workers.dev host, so that is a larger change upstream.
- **Check in `privateDeployment` (`scripts/lib-access-config.mjs`).** It already reads the selected environment's config before every deploy and in `--source-only`. Rule: a private (not open) deployment whose selected `routes` (or inherited top-level `routes`) is non-empty needs `workers_dev === true` (selected, else top-level). The error names `workers_dev` and `app/wrangler.jsonc`. Alternative: read `/workers/scripts/<name>/subdomain` in `checkPrivateAccess`. Rejected: the check runs before the deploy, which is the step that turns it off.
- **Open deployments are not checked.** They have no Access app to return to.

## Risks / Trade-offs

- [The workers.dev address answers beside the custom domain] → It sits behind the same Access app, as it did before the move; `checkPrivateAccess` already checks that Access covers it.
- [Upstream WongStack drift on `lib-access-config.mjs`] → Name it in the proposal, and send it upstream by hand.

## Migration Plan

Publish as usual. After the publish, `curl` the workers.dev address returns the Access redirect, not 404, and `cloudflared access login https://app.relayeverything.com` finishes. The address is on already, so nothing changes live until a later publish, which now keeps it on. Rollback: remove the key; the address goes off at the next publish.
