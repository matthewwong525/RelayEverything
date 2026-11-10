## Context

See proposal.md, Why. Two Workers serve the page today (`openspec/changes/archive/2026-11-10-flutter-web-app/design.md`):

- `relay-everything-server` (`app/worker/relay-only.ts`, `app/wrangler.relay.jsonc`) owns `app.relayeverything.com`, with no Access. Its `/` answers `302` to `/apps/relay/`. A self-hosted install runs the same Worker.
- `relay-everything` (`app/worker/index.ts`, `app/wrangler.jsonc`) owns `admin.relayeverything.com` behind Access, and serves the same build as the static mini app `relay` (`app/src/apps/relay/app.json`, `"static": true`). `build:app` builds the page with Flutter, and `deploy.yml` installs Flutter for it.

The Flutter build sits in `public/apps/relay/` with `<base href="/apps/relay/">`. `mobile/lib/main_web.dart` builds the `SpaceClient` base from the origin and `/apps/relay/`, so every API and sign-in call goes to `/apps/relay/api/…` and `/apps/relay/sign-in/…`, wherever the page shows. Flutter web uses its default hash address, so the page writes only `#/…` after its own path.

Checked on 2026-11-10, live: `app.relayeverything.com/` → `302 /apps/relay/` → `200`, no Access; `admin.relayeverything.com/apps/relay/` → Access login. Phones (`mobile/lib/data/connection.dart`), the AI connector (`RELAY_SERVER_URL` in `app/wrangler.relay-mcp.jsonc`) and the plugin already use app.relayeverything.com. A phone key made on the admin page would carry the admin origin, which the Access edge refuses with no service token, so no working phone points there now.

## Goals / Non-Goals

**Goals:**
- `https://app.relayeverything.com/` shows the app, with no move to another path and no company login.
- The admin site serves no copy of the app.
- Phones, the AI connector and sign-ins keep working.

**Non-Goals:**
- No redirect from an old admin link or from `/apps/relay/`: the person said old links do not matter.
- No change to `/apps/relay/api/…` or `/apps/relay/sign-in/…` routes, the Apple and Google callback addresses, the session cookie, Access policies or the database.
- No move of the page's files, and no second Flutter build.
- The company app keeps its relay API routes and the production webhook queue consumer.

## Decisions

### Serve `index.html` at `/`; keep the files under `/apps/relay/`

`relay-only.ts` answers `GET /` with the page's `/apps/relay/index.html`, in place of its `302`. The `<base href="/apps/relay/">` in it loads every file from `/apps/relay/`, and `pageOf` keeps the API base, so nothing in the build changes. The address bar shows `/` and then `#/…`. `/apps/relay/` still answers with the page, because its files must stay there and the page address costs no extra code; it is not a promise.

*Alternative:* build with `--base-href /` for the servers. Rejected: the company app's local dev and the self-host zip would need a second build, and asset paths at `/` could clash with later server routes.

### Sign-in returns to the page's address

`oidc.ts`'s `HOME` becomes `/`; `FAILED` becomes `/?signIn=failed`. `safeNext` takes `/`, or a path under `/apps/relay/`, and else `/`, so no other site can be named. `connect.ts` and `phone.ts` send a person with no sign-in to `/?next=…`. In Flutter, the Apple and Google start pass the window's own path (`Uri.base.path`) as `next` in place of `client.base.path`, so local dev at `/apps/relay/` still returns there. `nextOf` keeps taking only `/apps/relay/…` paths: every `next` the server sends is a sign-in route there.

### The admin site links out and builds no page

`listApps` (`app/src/apps/index.ts`) takes an optional `href` in `app.json`, an `https` address, for a card that opens another site. `app/src/apps/relay/app.json` sets `https://app.relayeverything.com/`. The folder and its `"static": true` stay, because `app/worker/apps/index.ts` guards the relay API routes by the card's `app.json`, and local dev still serves a page built by hand at `/apps/relay/`.

`build:app` drops `node ../scripts/build-relay-web.mjs`, and `deploy.yml` drops its Flutter step, so the company app ships no page: an old admin link gets the company app's own not-found. `publish-relay-server.mjs` and the release zip build the page as before. `mobile-ci.yml`'s `flutter test` runs `test/web_imports_test.dart`, which fails a phone-only import, so the check `deploy.yml` gave is kept for any change to `mobile/`.

*Alternative:* remove the `relay` folder. Rejected: the API guard fails without its `app.json`, and the owner loses the card.

### Phone and docs links

`account.dart`, `connected_names.dart` and `folder.dart` open `<server>/` and `<server>/#<part>`. A new phone that points at an older self-hosted server still works: that server's `/` sends to `/apps/relay/`, and the browser keeps the fragment. The docs pages in the proposal's Impact say `<your-relay-server>/`. `site/src/content/docs/api/keys.md` names only sign-in routes, which stay; `npm run relay:api-doc` runs to confirm the reference has no diff.

## Risks / Trade-offs

- [`Uri.base` in the page reads the document's base, not the window, and loses `next` at `/`] → a web test runs the page at `/?next=…` and at `/?signIn=failed`; if it fails, read the window's own address in `web_app.dart`, which already takes the page's address as a parameter.
- [Installed phones open `<server>/apps/relay/#webhooks`] → `/apps/relay/` still answers with the page, so those rows keep working.
- [A cached `/` answer from the old server] → its `302` had no cache header, so browsers ask again.
- [The owner's admin session does not carry over] → the owner signs in once at app.relayeverything.com with the same email; the space is the same (the owner signed up there with Google on 2026-11-06).

## Migration Plan

1. Merge. The publish deploys the company app with no page; `node scripts/publish-relay-server.mjs` then deploys the staging and live shared servers.
2. Check on live: `/` shows the sign-in with no `Location`, the admin card opens app.relayeverything.com, a phone syncs.
3. Roll back with `publish-relay-server.mjs --ref <earlier commit>` and a publish of the earlier company app.
