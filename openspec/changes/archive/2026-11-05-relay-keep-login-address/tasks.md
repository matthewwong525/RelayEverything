# Tasks

## 1. Keep the address on

- [x] 1.1 Add top-level `"workers_dev": true` to `app/wrangler.jsonc`, beside `routes`.

## 2. Refuse a config that turns it off

- [x] 2.1 In `privateDeployment` (`scripts/lib-access-config.mjs`), throw for a private deployment whose selected or inherited `routes` is non-empty and whose `workers_dev` is not `true`; the message names `workers_dev` and `app/wrangler.jsonc`.
- [x] 2.2 Add tests beside the existing ones: routes with no `workers_dev` fails; routes with `workers_dev: true` passes; staging with `routes: []` passes; an open deployment is not checked.

## 3. Wiki

- [x] 3.1 Add one bullet to *Move a Worker to a new name* in `wiki/stack/move-cloudflare-data.md`: give a Worker a custom domain and keep `workers_dev: true`, or Access returns each sign-in to a dead address.

## 4. Verify

- [x] 4.1 Run the access-config tests, `node scripts/check-private-access.mjs --environment production --source-only`, and the repo's `npm test` chain.
