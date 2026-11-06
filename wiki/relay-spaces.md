# Relay Everything's person spaces

Each person's Relay Everything data lives in their own space: one SQLite-backed Durable Object, opened only for that person's checked sign-in, device key or AI app grant. This page tells how a space is opened, the check that keeps it that way, the shared directory, the space's migrations, sealed recordings, and the one-time move. It is part of [the wiki](README.md); the website's [Privacy](../site/src/content/docs/privacy.md) page owns what a person reads about it, and [the plan](../openspec/changes/relay-person-spaces/design.md) owns why it has this shape.

## How a space is opened

1. The Worker's gate asks [`caller.ts`](../app/worker/apps/relay/caller.ts) who calls: a device key (`Authorization: Bearer rek_…`, looked up by SHA-256 in `relay_keys`), the preview checker (its Client ID's SHA-256 is `RELAY_CHECKER_SHA256`), a session cookie (`__Host-relay_session`), or, on a server that signs in with Access, Access's email. The answer is cached per request, so the route gets the same caller.
2. Only a checked identity becomes a caller, through `vouch` in [`space.ts`](../app/worker/apps/relay/space.ts). A few files may call `vouch`: the caller check, the sign-in, the AI connector's sign-in and tools, the webhooks' queue consumer, and the move.
3. A route calls `spaceOf(env, caller)`. It names the space by the caller's random person id, never by an id from the request, and gives back a `Db` in D1's shape, so each route keeps its own SQL.
4. A device key adds data only, to its own person's space: `reaches` in `caller.ts` holds it to its routes. A person's routes refuse a key.

The [`Space`](../app/worker/spaces-worker.ts) class lives in its own Worker, `relay-everything-spaces` (`-staging`, `-local`, and `<name>-spaces` on a self-host), bound as `SPACES` by `script_name`, because a Worker that holds a Durable Object class loses its preview links, as with [the live line](stack/live-line.md). Deploy the spaces Worker before the app, so the binding finds its class.

## The one-door rule

Only `space.ts` opens a space or the file store. [`space-access.test.ts`](../app/worker/apps/relay/space-access.test.ts) reads the worker source and fails when another file names `SPACES.`, `idFromName` or `RELAY_BUCKET`, or calls `vouch` outside its allowed files. Don't add an exception: an owner screen or tool that opens another person's space breaks the promise on the privacy page. Route tests show Ana's session, key and AI grant each reach only Ana's rows, with Ben's ids in the request.

## The directory

The shared D1 database keeps only who has an account and how they sign in, in [`20261107120000_relay_people.sql`](../schema/migrations/20261107120000_relay_people.sql): `relay_people` (a random id and the email), `relay_logins` (Apple and Google subjects), `relay_sessions`, `relay_sign_in_codes`, `relay_keys`, `relay_connect_codes` (the AI connector's single-use codes) and `relay_move_tickets`. Each code, session and key is kept only as its SHA-256. No note, sample, place, chat or recording goes in the directory.

## Space migrations

A space runs [`schema/space-migrations/`](../schema/space-migrations/) in order, in its constructor under `blockConcurrencyWhile`, and records each in its `space_migrations` table. `0001_relay.sql` is the D1 `relay_*` schema as is; a test compares a new space's schema with D1's after the `relay` migrations, so the two can't drift. `0002_space.sql` adds what only a space has: its file key, each Pebble device's signing secret, and the person the alarm sends for.

A new space table goes in a new numbered file: never edit one a space already ran.

## Recordings

A recording's file store key is `people/<person id>/<note id>`. Each is sealed with AES-256-GCM: a fresh 12-byte IV per object, the space's own 256-bit file key from `space_keys`, and the store key as associated data, so a copy under another name fails to open. `audio.ts` opens a recording only through the caller's space; deleting the space deletes the file key, and account deletion also deletes every object under the prefix.

## Webhooks

The send log, `relay_outbox`, and `relay_webhooks` live in each space. A queue message carries the webhook and its person, and the consumer opens that person's space. Each space with a webhook sets an alarm every 15 minutes, which wakes any webhook left behind and drops tries older than 30 days. No job walks over all spaces, and a space with no webhook costs nothing.

## The move

`scripts/relay-move-to-space.mjs` moves the owner's data from the old D1 `relay_*` tables into the owner's space. It writes a ticket to `relay_move_tickets` with the deploy key, then the server reads the old tables a page at a time, writes each page through the space's write-only `import` (`INSERT OR IGNORE` on the same ids), and seals each recording into the owner's folder. It prints the count of each kind and `result=ok`, `result=mismatch` or `result=failed`. A mismatch is a kind the space holds fewer of than the old tables: the old tables stay as they were, while the space grows from use. It is safe to run again. The old tables stay until the owner confirms the counts; a later change drops them. A self-host's update runs the same move: [`self-host/SETUP.md`](../self-host/SETUP.md).

## The Workers and their order

Three Workers serve Relay Everything, and each deploy goes in this order, because Cloudflare refuses a binding to a Worker that does not exist:

1. The spaces Worker, [`app/wrangler.spaces.jsonc`](../app/wrangler.spaces.jsonc): the `Space` class, with no web address.
2. The AI connector, [`app/wrangler.relay-mcp.jsonc`](../app/wrangler.relay-mcp.jsonc), which binds `SPACES`.
3. The shared server, [`app/wrangler.relay.jsonc`](../app/wrangler.relay.jsonc), and the company app, [`app/wrangler.jsonc`](../app/wrangler.jsonc), which both bind `SPACES` and the connector.

A publish deploys the live spaces Worker, the connector and the company app ([`scripts/cf-deploy.sh`](../scripts/cf-deploy.sh)). A preview deploys only the company app, so deploy a branch's spaces Worker from `app/` by hand: `npx wrangler deploy -c wrangler.spaces.jsonc --env staging`.

The shared server is built through the relay-only build, then deployed by hand:

```bash
RELAY_CONFIG=wrangler.relay.jsonc CLOUDFLARE_ENV=staging npm run build:relay-only   # leave out CLOUDFLARE_ENV for live
npx wrangler deploy                                                               # follows the build's redirect
```

The shared server shares the company app's database, bucket and queue. On production the company app keeps the queue's one consumer. Staging is different: previews reach no other Worker's objects ([the live line](stack/live-line.md)), so the company app's staging Worker has no `SPACES`, its relay routes answer 503, and the staging shared server consumes the queue. Until the switch, the company app holds `app.relayeverything.com`: at the switch, take the address off the company app first, then deploy the live shared server, which claims it.

## See also

- [Relay Everything's AI connector](stack/relay-ai-connector.md): each grant carries its person id and reads that space.
- [Relay Everything's Claude Code chats](stack/relay-chats.md): a chat key adds chats to its own person's space.
- [The Relay Everything website](relay-website.md): a change here updates its pages in the same change.
