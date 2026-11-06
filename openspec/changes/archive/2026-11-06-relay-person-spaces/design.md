# Design

## Context

Relay Everything keeps all its data in one D1 database, `DB` (`relay-everything-db`, staging `relay-everything-db-staging`, self-host `<name>-db`). The `relay_*` tables (`relay_devices`, `relay_notes`, `relay_health`, `relay_locations`, `relay_chats`, `relay_chat_messages`, `relay_chat_saves`, `relay_outbox`, `relay_webhooks`, `relay_webhook_attempts`) have no person column. Every row hangs off `relay_devices`. Recordings are in R2 (`RELAY_BUCKET`). Identity comes from Cloudflare Access: one owner email (`WONG_OWNER_EMAIL`), plus Access service tokens as device keys (`device.ts` `deviceGate`, made by `scripts/relay-device-key.mjs`). The AI connector (`relay-mcp`) signs in through Access for SaaS and admits only the owner. Webhooks use a queue (`RELAY_WEBHOOKS`) and a 15-minute cron sweep over `relay_outbox`.

Two Workers serve these routes: the company app (`app/worker/index.ts`, `/apps/relay/` among WongStack's apps) and the relay-only Worker (`app/worker/relay-only.ts`) that self-hosts install. The live line already shows the pattern for a Durable Object that keeps preview links: the class lives in its own Worker (`line-worker.ts`), and the app binds it by `script_name`.

## Goals / Non-Goals

**Goals:**
- One Durable Object per person, with its own SQLite, holding all of that person's Relay Everything data.
- Open sign-up on the shared server, with no cost per person.
- No code path that opens a space from anything but the caller's own verified identity, enforced by a check.
- The same storage code on the shared server, staging, local and self-hosted servers.
- Move the owner's data with counts, and no loss.

**Non-Goals:**
- Tiers, payment, storage limits.
- Phone-side (end-to-end) encryption. The Cloudflare account owner can still deploy code that reads a space; the privacy page says so.
- An admin or support view of other people's data.

## Decisions

### 1. A `Space` Durable Object in its own Worker

`app/worker/spaces-worker.ts` exports `class Space extends DurableObject` (SQLite-backed: `new_sqlite_classes` in `app/wrangler.spaces.jsonc`). Workers: `relay-everything-spaces`, `relay-everything-spaces-staging`, `relay-everything-spaces-local`, and `<name>-spaces` for a self-host. The app, relay-only and connector Workers bind it as `SPACES` with `script_name`, as `LIVE_LINE` is bound. A Worker that holds a Durable Object class loses preview links, so the class stays out of the app Worker.

Alternative: one D1 database per person. Rejected: D1 bindings are fixed in the Wrangler file, so a new person would need a redeploy or the D1 REST API, and an account allows a limited number of databases.

### 2. A space is named by a random person id

`env.SPACES.idFromName(person.id)`, where `person.id` is a random UUID in the directory. It is not the email: a changed email keeps its space, and no email shows in a Durable Object name.

### 3. The space runs SQL and nothing else

The `Space` class exposes RPC methods (`query(sql, params)`, `batch(statements)`, plus `deleteEverything()`). The routes keep their SQL. `store.ts` gives them a `Db` that wraps a space stub in place of `env.DB.withSession(...)`. So the change to each route is where its `Db` comes from, not its SQL. Space migrations live in `schema/space-migrations/NNNN_*.sql`, bundled into the spaces Worker, and run in the constructor under `ctx.blockConcurrencyWhile`. The applied version is kept in a `space_migrations` table. The first migration is today's `relay_*` schema, as is.

Alternative: one RPC method per route. Rejected for now: it means rewriting every route at once. Passing SQL is safe here because only these trusted Workers hold the binding, and no request names a space.

### 4. One way to open a space

`app/worker/apps/relay/space.ts` exports `spaceOf(env, caller)`, where `caller` is the verified identity (a session, a device key or a connector grant) that the sign-in code resolved to a `personId`. It is the only file that calls `SPACES.idFromName` or `SPACES.get`. A test (`space-access.test.ts`) reads the worker source and fails when any other file names `SPACES.` or `idFromName`, or when `spaceOf` takes anything but a resolved caller. Route tests show that Ana's session, key and grant each get Ana's rows and never Ben's, whatever ids are in the request.

### 5. The directory stays in D1

New tables in `schema/migrations/` (shared D1): `relay_people (id, email UNIQUE, created_at)`, `relay_logins (provider, subject, person_id)` for Apple and Google, `relay_sessions (token_sha256 PK, person_id, expires_at)`, `relay_sign_in_codes (email, code_sha256, expires_at, tries)`, and `relay_keys (key_sha256 PK, person_id, device_id, reaches, revoked_at)`. The directory holds no data. A key check needs one D1 read, then one space call.

### 6. The server's own sign-in, outside Access, on the shared server

The shared server is the relay-only Worker on `app.relayeverything.com`, with no Access app in front. New routes under `/apps/relay/sign-in/`: email code, sent through Cloudflare Email Service by a `send_email` binding from `sign-in@relayeverything.com` (6 digits, 10 minutes, 5 tries, limited per email and per IP with a Workers rate-limit binding), and Apple and Google by OIDC (code flow with PKCE and `state`, ID token checked against the provider's JWKS, `email_verified` required). The session is a 32-byte random token in a `__Host-relay_session` cookie (`HttpOnly`, `Secure`, `SameSite=Lax`), kept 30 days, stored by SHA-256. Every state-changing route needs a same-origin `Origin` header. The company app's `/apps/relay/` redirects to the shared server.

The public sign-in values sit in the shared server's Wrangler vars: Services ID `com.matthewwong525.relayeverything.signin` (primary App ID `com.matthewwong525.relayeverything.web`), and Google client `20665982462-kf2e6v2vd3jofia52g0d9p5vn1gt4hfu.apps.googleusercontent.com` (project `relay-everything`, in production). The secrets are `RELAY_APPLE_SIGN_IN_KEY`, `RELAY_APPLE_SIGN_IN_KEY_ID`, `RELAY_GOOGLE_SIGN_IN_SECRET` and the Apple team ID, `RELAY_APPLE_TEAM_ID` (`app/.dev.vars.example`). The team ID is not secret, but `.env` holds it, so the public-repo check refuses it in a committed file. The return addresses on both lists are `https://app.relayeverything.com/apps/relay/sign-in/{apple,google}/callback`, the same on `app-staging.relayeverything.com` (staging's fixed address, since preview addresses can't be listed), and Google's `http://localhost:8787/…` for local runs. Email codes come from `sign-in@relayeverything.com`; Email Sending is on for the zone.

On a self-hosted server, `RELAY_SIGN_IN=access` keeps Cloudflare Access. The Access email maps to a person row, and only `WONG_OWNER_EMAIL` gets one until the owner sets `RELAY_SIGN_UP=open`. The sign-in code is one module with two sources of a verified email. Everything after it is shared.

### 7. Device keys made by the server

*Add a device* on the page makes `rek_<base64url 32 bytes>`, shows it once as a QR code (the same QR flow the phone already scans), and stores only its SHA-256 in `relay_keys`. Devices send `Authorization: Bearer <key>`. `deviceGate` keeps its reach rules (`phone`, `chats`) and its methods, now read from `relay_keys`. The Pebble address becomes `/apps/relay/api/pebble/<device id>`, with a signing secret per person kept in the space and shown once. The phone app accepts both key formats for one release, so the switch does not strand phones. `scripts/relay-device-key.mjs` remains only for a self-host that keeps Access service tokens until its update.

The preview checker keeps its own path: on staging only, a `RELAY_CHECKER_KEY` secret signs in as a fixed test person. Its SHA-256 sits in `app/wrangler.jsonc`, as `RELAY_CHECKER_SHA256` does today.

### 8. The connector signs in through the server

`relay-mcp`'s `/authorize` sends the person to the server's sign-in page, which returns to `/callback` with a short-lived, single-use code redeemed over the service binding. The OAuth grant's props hold `personId`, and each tool calls `spaceOf` with it. `ai-apps.ts` lists and ends only the signed-in person's grants. This drops Access for SaaS from the connector on the shared server. A self-host keeps it, mapped to the owner.

### 9. Webhooks per space

`relay_outbox`, its triggers and `relay_webhooks` move into the space unchanged. A queue message gains `personId`, and the consumer opens that space through `spaceOf` with a queue caller that the producer itself built. The 15-minute cron sweep becomes a Durable Object alarm in each space that has a webhook behind. No job walks over all spaces.

### 10. Recordings under the person's folder, locked by the space

R2 keys become `people/<person id>/<note id>`. Each space makes a random 256-bit file key on first use and keeps it in its own SQLite (`space_keys`); it never leaves the spaces Worker except to `spaceOf`'s caller. Each object is sealed with AES-256-GCM (a fresh 12-byte IV per object, the R2 key as associated data, so a file moved to another name or folder fails to open). `notes.ts` and `pebble.ts` seal before `put`; `audio.ts` checks the note in the caller's space, reads that key, and opens it. Only `space.ts` touches `RELAY_BUCKET`; the check in Decision 4 covers it. The Cloudflare dashboard then shows only sealed bytes. Deleting the space deletes the file key, so a leftover object can't be opened. On account deletion, every object under the prefix is listed and deleted.

### 11. Moving the owner's data

`scripts/relay-move-to-space.mjs --person <owner email> [--staging]` reads each old `relay_*` table through the Cloudflare D1 API in pages, writes them to the owner's space through a write-only `import` RPC, seals each R2 object with the owner's file key into the new prefix, and prints counts per kind (`result=ok|mismatch|failed`). Inserts use `INSERT OR IGNORE` on the same primary keys, so a re-run is safe. A later migration, `drop_old_relay_tables`, ships in its own change only after the owner confirms the counts. Self-host's `setup.mjs update` runs the same move for its owner.

## UX

### Brief
- **Who:** a new person who got a ring or the phone app and wants an account; and the current owner, who keeps using their data.
- **Job:** sign in, then connect a phone.
- **Done:** the timeline shows their first note.
- **Context:** on a phone or a laptop, once. Adding a device happens a few times per account.
- **Common case:** email code. **Edge:** Apple or Google, a wrong or expired code, account deletion.
- **Closest screen:** the server page's current *connect a phone* card, and the phone's existing QR scan screen.

### Flow
1. Open the server address → sign-in page.
2. Enter email → *Email me a code* → enter code → timeline (empty for a new person).
3. *Add a device* → name it → QR shown once → scan with the phone.

### Hierarchy and parts
- Sign-in page: one primary action, *Email me a code*. Apple and Google are ghost buttons above. Uses `card`, `field`, `btn-primary`, `btn-ghost`.
- Settings: *Add a device* (primary), the device list with *Turn off*, then *Delete my account* (danger, confirm by typing the email) at the bottom.

### Review
[review.html](review.html). The sign-in sketch is in What Changes, item 1. *Add a device* and *Delete my account* use the existing settings layout and are described in items 4 and 7.

## Risks / Trade-offs

- **The account owner can still read a space** by deploying code → stated on the privacy page. The code is public. Phone-side encryption is a later choice.
- **Own sign-in is new attack surface** (code guessing, session theft, OAuth mix-ups) → codes and sessions are stored hashed, with limits per email and IP, PKCE and `state`, `__Host-` cookies, and Origin checks. Each has a test.
- **Spam sign-ups cost storage and email** → rate limits now. Tiers come later.
- **Cloudflare Email Sending is in beta** → the sender sits behind one function, `sendCode`, so another sender can replace it without touching the sign-in routes.
- **Phones that are not updated stop sending at the switch** → the phone accepts both key formats a release ahead, and the switch waits until the owner's devices run it.
- **SQL over RPC** → only `spaceOf` makes a stub, and the check in Decision 4 keeps it that way.
- **Per-space alarms in place of one sweep** → a space with no webhook sets no alarm, so idle people cost nothing.
- **Emails in the directory** → needed to sign in. The directory holds nothing else about a person.

## Migration Plan

1. Ship the phone app that accepts both key formats.
2. Before publish, on staging: deploy the spaces Worker, the connector and the shared server on `app-staging.relayeverything.com`. Run the move on staging and check the counts.
3. Publish. The company app's relay routes now read spaces, so the live app is down until step 5: the owner chose this over a longer build that keeps D1 until the switch.
4. Right after publish, with the owner: take `app.relayeverything.com` off the company app, deploy the live shared server there, and set its sign-in secrets.
5. The owner signs up with their email, the move runs, and the counts are checked.
6. The owner makes new keys on the page and rescans each device, the Pebble app and the plugin, and connects the AI connector again.
7. A follow-up change adds the company app's `/apps/relay/` redirect and turns off the old Access service-token keys.
8. A separate change drops the old tables after the owner confirms.

Rollback before step 7: the old D1 data is untouched, so pointing the routes back at `env.DB` restores the old server.
