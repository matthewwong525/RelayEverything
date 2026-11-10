# Email notes at notes@relayeverything.com

**Status:** ready-to-ship
**Branch:** fix-notes-email-domain
**Open questions:** none

## Why

Email notes use the address `notes@in.relayeverything.com`. The `in.` part is one subdomain too many: it is harder to say, type and remember. The main domain can take the same mail on the same server, so the address can be short and simple.

## What Changes

- **The note addresses drop `in.`.** You write to `notes@relayeverything.com` from your sign-in email. Your own secret address becomes `notes-<code>@relayeverything.com`, with the same code. The same server takes the mail: there is no new server and no new Cloudflare setting.
  ```text
  Before: notes@in.relayeverything.com
          notes-k7q2m9xw@in.relayeverything.com
  After:  notes@relayeverything.com
          notes-k7q2m9xw@relayeverything.com
  ```

- **The old `in.` addresses stop.** Mail to an address that ends with `@in.relayeverything.com` makes no note. Mail rules and contacts that use the old address need the new one. The *Email notes* page in Settings shows the new address at once.
  ```mermaid
  flowchart TD
    N["notes-…@relayeverything.com"] --> S["Relay Everything server"] --> Note["A note"]
    O["notes-…@in.relayeverything.com"] --> X["No note"]
  ```

- **Your other addresses stay as they are.** `matt@` and `privacy@relayeverything.com` keep their own rules, so their mail does not go to notes. Only addresses that start with `notes` make a note. The server refuses mail to every other address on the domain, as it does now.
  ```mermaid
  flowchart TD
    M["Mail to relayeverything.com"] --> R{"Which address?"}
    R -- "matt@, privacy@" --> F["Their own rule, as now"]
    R -- "notes@, notes-…@" --> N["A note"]
    R -- "any other" --> X["Refused"]
  ```

- **The website needs no change.** Its pages already say "`notes@` and your server's mail domain", because the site may not hold a full email address. Your *Email notes* page in Settings shows the full new address. A server that you run yourself still picks its own mail domain: a subdomain stays the safe choice when your own domain already gets mail elsewhere.
  ```text
  Website:   notes@ + your mail domain  (same)
  Settings:  notes@relayeverything.com  (new)
  ```

## What the build needs

- **Mail to the main domain**: Ready. The main domain's catch-all rule already sends every address with no rule of its own to `relay-everything-server` (checked on 2026-11-10). No key or account is needed.
- **The old `in.` subdomain**: Ready. It can stay: the server refuses its mail. Removing it later is one optional click in the Cloudflare dashboard, after the switch.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-inbox`: the shared server takes note mail on relayeverything.com itself, not on a subdomain; the old `in.` addresses make no note.

## Impact

- `app/wrangler.relay.jsonc`: live `RELAY_INBOX_MAIL_DOMAIN` becomes `relayeverything.com`; staging keeps `in-staging.relayeverything.com`.
- No code change: `inbox/links.ts` builds every address from that setting, and `inbox/email.ts` refuses any other domain. The `relay_inbox_links` rows keep only the local part, so each person keeps their code.
- `wiki/relay-spaces.md#ways-in` (the live mail domain) and the example in `app/.dev.vars.example`. No `site/` page changes: the site guard refuses a full email address, and the pages name none.
- Publish: `node scripts/publish-relay-server.mjs` puts the new setting live.

## Decision log

**2026-11-10** — Asked why the address had `in.`, then told to use `notes@relayeverything.com`, because `in.` is too many subdomains and things should be elegant and simple → chose the main domain, on the same server.

**2026-11-10** — Assumed: the old `in.` addresses stop with no grace period, because Matthew wants it simple and said on app-subdomain that old links don't matter; accepting two domains would add a second setting to keep.

**2026-11-10** — Assumed: staging keeps `in-staging.relayeverything.com`, because a zone has one catch-all, which goes to the live server, and nobody outside sees staging's address.

**2026-11-10** — Assumed: a self-hosted server keeps the advice to pick a subdomain, because a domain whose mail goes to another service, such as Gmail, can't also route mail to the Worker.

**2026-11-10** — Assumed: personal addresses keep the `notes-<code>` form and their code, because only the domain was too long, and a new code would make every person copy a new address twice.

**2026-11-10** — Told, during `/ship`, to also remove the `in.` subdomain → it is removed in Cloudflare after the live publish, so note mail never has a gap; it is a dashboard step, not a repository task.

**2026-11-10** — Assumed: the example in `app/.dev.vars.example` names the main domain first and keeps a subdomain for a domain that gets mail elsewhere, because the self-host advice stays as it is. The task's check `grep "in\.relayeverything"` also matches `admin.relayeverything.com`; only that address remains, so it passes.

**2026-11-10** — Assumed: the `/save` task is dropped, because `/ship` runs `/save` and waits for CI before it merges; the live publish and the test mail run after the merge (design.md, Migration Plan).

**2026-11-10** — Archive checkpoint: built and reviewed (review found nothing to fix); local checks passed; saved inside `/ship`.
