# Tasks

## 1. The servers

- [x] 1.1 `app/worker/relay-only.ts`: `GET /` serves the page's `/apps/relay/index.html` in place of the `302`; `/apps/relay/`, its files, `api/` and `sign-in/` unchanged. Tests cover `/` (`200`, the page, no `Location`), `/apps/relay/` and an `api/` route.
- [x] 1.2 `app/worker/apps/relay/sign-in/`: `oidc.ts` returns to `/` (`FAILED` `/?signIn=failed`), `safeNext` takes `/` or `/apps/relay/…`, else `/`; `connect.ts` and `phone.ts` send a person with no sign-in to `/?next=…`. Update `oidc.test.ts`, `connect.test.ts` and the phone sign-in tests, with a case that a `next` to another site still goes to `/`; the Apple and Google `redirect_uri` stay as they are.
- [x] 1.3 `app/src/apps/index.ts`: `listApps` takes an optional `https` `href` from `app.json` for the card, and refuses any other value; `app/src/apps/relay/app.json` sets `https://app.relayeverything.com/`. Tests in `app/src/apps/index.test.ts`; the home card renders the outside link.
- [x] 1.4 `app/package.json` `build:app` drops the web build; `.github/workflows/deploy.yml` drops the Flutter step and its comment. Verify `npm run build:app` makes no `public/apps/relay/index.html` from a clean folder, and `scripts/build-relay-web.test.mjs` and the self-host tests still pass.

## 2. The app

- [x] 2.1 `mobile/lib/web/sign_in.dart`: Apple and Google pass the window's own path as `next`. `mobile/lib/main_web.dart` comments name the page at `/`. Web tests: the page at `/?next=/apps/relay/sign-in/connect?x` goes on to that address after sign-in, and `/?signIn=failed` shows the failure.
- [x] 2.2 `mobile/lib/screens/account.dart`, `connected_names.dart`, `folder.dart`: open `<server>/` and `<server>/#<part>`. Update `mobile/test/screens_test.dart`; `flutter test` passes.

## 3. Docs

- [x] 3.1 `site/src/content/docs/`: `app/email.md`, `app/on-a-computer.md`, `app/settings.md`, `app/your-notes.md`, `connections/your-database.md`, `start/connect-a-phone.md`, `start/sign-up.md` say `<your-relay-server>/`. `npm run relay:api-doc` in `app/` leaves no diff; `node --test scripts/product-name.test.mjs` passes.
- [x] 3.2 `wiki/relay-spaces.md` (the page opens at the shared server's `/`, the admin site has no copy, and local dev builds it first with `node ../scripts/build-relay-web.mjs`), `wiki/stack/mini-apps.md` (a card's outside `href`), `app/self-host/SETUP.md`, `mobile/README.md`.

## 4. Checks

- [x] 4.1 `npm test` in `app/` and `flutter test` in `mobile/` pass; `/save`, and CI passes.
- [x] 4.2 After `node scripts/publish-relay-server.mjs --staging-only`, on `app-staging.relayeverything.com`: `/` shows the sign-in with no `Location`; `/?signIn=failed` shows the failure; *Sign in with Google* asks Google to come back to `/`; a phone's connect and the AI connector's sign-in, signed out, send to `/?next=…`.
