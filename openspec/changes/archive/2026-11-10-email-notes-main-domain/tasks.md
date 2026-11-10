# Tasks

## 1. Move the live mail domain

- [x] 1.1 Set live `RELAY_INBOX_MAIL_DOMAIN` to `relayeverything.com` in `app/wrangler.relay.jsonc`, leaving staging on `in-staging.relayeverything.com`; verify with `grep RELAY_INBOX_MAIL_DOMAIN app/wrangler.relay.jsonc`
- [x] 1.2 Update `wiki/relay-spaces.md#ways-in` (live domain is the zone itself; the catch-all sends it to `relay-everything-server`; `matt@` and `privacy@` keep their rules) and the example in `app/.dev.vars.example`; verify no `in.relayeverything` remains outside `openspec/` with `grep -rn "in\.relayeverything" --exclude-dir=node_modules --exclude-dir=openspec .`

## 2. Checks

- [x] 2.1 Run the inbox tests (`npx vitest run worker/apps/relay/inbox` in `app/`) and `node scripts/product-name.test.mjs`; both pass
