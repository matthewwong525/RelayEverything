# Design

## Context

Checked on 2026-11-10 through the Cloudflare API on the `relayeverything.com` zone:

- MX records: the apex and `in.` both point to Cloudflare Email Routing (`route1-3.mx.cloudflare.net`).
- Rules: `matt@` → a Worker, `privacy@` → forward, `notes@in-staging.` → `relay-everything-server-staging`.
- The catch-all is on and sends to `relay-everything-server`. Today the server refuses apex mail because its domain is `in.relayeverything.com`.

`inbox/links.ts` reads the domain from `RELAY_INBOX_MAIL_DOMAIN` and builds each address as `<shown>@<domain>`. `relay_inbox_links.shown` keeps only the local part, and the lookup is an HMAC of the local part. `inbox/email.ts` refuses mail whose domain is not the setting. So the domain is one setting, and no stored data names it.

## Goals / Non-Goals

**Goals:** live note mail on `relayeverything.com`, with the same server and each person's same code.

**Non-Goals:** taking two domains at once; a change to staging's `in-staging.` domain; a change to self-host advice; new Cloudflare rules.

## Decisions

- **Change the setting, not the code.** Live `RELAY_INBOX_MAIL_DOMAIN` becomes `relayeverything.com`. The alternative, a list of accepted domains to keep `in.` working for a while, adds a setting and a test for a few addresses, against the person's ask for simple.
- **Keep staging on `in-staging.`.** A zone has one catch-all, and it goes to live. Staging on the apex would need a literal rule for each test address, and it would share `notes@` with live.
- **Leave `matt@` and `privacy@` as they are.** A literal rule wins over the catch-all, so their mail never reaches the server.
- **Remove the `in.` subdomain only after the switch, by hand.** The repository's token gets an Authentication error on Email Routing settings, so the person or a browser session does it in the dashboard. Left in place, its mail still reaches the server, which refuses it.

## Risks / Trade-offs

- [A person's mail rule still sends to the old `in.` address] → their notes stop with no answer. Mitigation: the *Email notes* page shows the new address at once; few people use email notes yet.
- [Mail to a mistyped apex address now reaches the server] → it does today too, through the catch-all; the server refuses it.

## Migration Plan

1. Merge, then run `node scripts/publish-relay-server.mjs`: the live server takes `relayeverything.com`.
2. Send one mail to `notes@relayeverything.com` from the owner's sign-in email and see the note.
3. Optional: remove the `in.relayeverything.com` subdomain in the dashboard.

Rollback: set the value back to `in.relayeverything.com` and publish again.
