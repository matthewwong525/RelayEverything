# Relay Everything opens at app.relayeverything.com, for everyone, with no company login

**Status:** ready-to-ship
**Branch:** hesitant-rhino
**Open questions:** none

## Why

The Relay Everything app is for the public, but the link to it was the company admin address, which asks for the company login. The app already runs, open to all, on app.relayeverything.com, but there it opens at `app.relayeverything.com/apps/relay/`. People should open the app at app.relayeverything.com, with no login wall and no extra path.

## What Changes

- **The app opens at app.relayeverything.com.** Open the address and the app's sign-in or your notes show at once, at `app.relayeverything.com/`. There is no company login: anyone can sign up with an email code, Apple or Google. A server you run yourself opens its app at its own top address too.
  ```mermaid
  flowchart TD
    A["app.relayeverything.com"] --> S{"Signed in?"}
    S -- "no" --> I["Sign in"]
    S -- "yes" --> N["Your notes"]
    I --> N
  ```

- **The admin site drops its copy of the app.** admin.relayeverything.com no longer serves the app. Its *Relay Everything* card opens app.relayeverything.com. Nothing redirects: an old admin link to the app goes nowhere.
  ```mermaid
  flowchart TD
    C["Admin: Relay Everything card"] --> A["app.relayeverything.com"]
    O["Old admin link to the app"] --> X["No app there"]
  ```

- **Phones, the AI connector and sign-ins keep working.** Phones already send to app.relayeverything.com, so a signed-in phone changes nothing. The phone's *Open your Relay Everything page* row opens the new address. Signing in with Apple or Google, connecting a phone, and connecting an AI app come back to the app at the new address. The admin copy used the company login, so you sign in once at app.relayeverything.com, with the same email, and see the same notes.
  ```mermaid
  sequenceDiagram
    participant B as Browser
    participant A as Relay Everything
    participant G as Google
    B->>A: Sign in with Google
    A->>G: Who is this?
    G-->>A: Your email
    A-->>B: Back to the app, signed in
  ```

- **The website and docs name the new address.** Each page that says to open `<your-relay-server>/apps/relay/` now says `<your-relay-server>/`.
  ```text
  Before: open <your-relay-server>/apps/relay/
  After:  open <your-relay-server>/
  ```

## What the build needs

- **Nothing.** The address app.relayeverything.com is already Relay Everything's, and Apple and Google already return to it, so no new key, account or sign-in setting is needed.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-web-app`: the page opens at the server's top address; the company app no longer serves it.
- `relay-server-address`: the shared server's top address shows the app with no company login; the company app only links there.

## Impact

- `app/worker/relay-only.ts`: `GET /` serves the page's `index.html` in place of a `302` to `/apps/relay/`; `/apps/relay/` and its files, `api/` and `sign-in/` routes stay as they are.
- `app/src/apps/index.ts` and `app/src/apps/relay/app.json`: a mini app's card may name an outside `href`; the Relay Everything card names `https://app.relayeverything.com/`.
- `app/package.json` (`build:app`) and `.github/workflows/deploy.yml`: the company app's build no longer builds the Flutter page, and its CI no longer installs Flutter. `mobile-ci.yml`'s `flutter test`, with `test/web_imports_test.dart`, still fails a phone-only import.
- `app/worker/apps/relay/sign-in/`: `oidc.ts`, `connect.ts` and `phone.ts` return to `/` instead of `/apps/relay/`; a `next` under `/apps/relay/` is still taken. The Apple and Google callback addresses do not change.
- `mobile/lib/`: `web/sign_in.dart` (sign-in returns to the page's own path); `screens/account.dart`, `screens/connected_names.dart`, `screens/folder.dart` open `<server>/` and `<server>/#<part>`.
- `site/src/content/docs/`: `app/email.md`, `app/on-a-computer.md`, `app/settings.md`, `app/your-notes.md`, `connections/your-database.md`, `start/connect-a-phone.md`, `start/sign-up.md`.
- `wiki/relay-spaces.md` (a branch's page in local dev needs `node ../scripts/build-relay-web.mjs` first), `wiki/stack/mini-apps.md`, `app/self-host/SETUP.md`, `mobile/README.md`.
- No Access policy, cookie, Apple or Google setting, database or route under `api/` changes.

## Decision log

**2026-11-10** — Assumed: "app.relay" means app.relayeverything.com, because that address is already the shared Relay Everything server and staging is app-staging.relayeverything.com.

**2026-11-10** — Asked whether people should see `app.relayeverything.com/` or keep `app.relayeverything.com/apps/relay/` → chose the clean `app.relayeverything.com/`, with old `/apps/relay/` links forwarding.

**2026-11-10** — Told, during planning, that the app must not have a password because the public uses it → the plan keeps app.relayeverything.com free of the company login, as it is today.

**2026-11-10** — Assumed: the page's files stay under `/apps/relay/` and only its address moves, because one build then serves the shared server, a self-hosted server and the company app's local dev, and the self-host zip stays the same.

**2026-11-10** — Asked, in a note with */ship*, for no redirects because old links don't matter → done: no forward from admin or from `/apps/relay/`. The admin site drops its copy of the app and its card links to app.relayeverything.com. `/apps/relay/` still opens the app on app.relayeverything.com, because the app's files live there and keeping it costs no code.

**2026-11-10** — Assumed: the admin card stays, as a plain link to app.relayeverything.com, because the company app's relay API needs the card's `app.json` to stay guarded (`app/worker/apps/index.ts`), and the link is the owner's way to the app.

**2026-11-10** — Assumed: the company app's build stops building the Flutter page, and its CI stops installing Flutter, because the admin site no longer serves the page; `mobile-ci.yml`'s `flutter test` still catches a phone-only import.

- **2026-11-10** — Check: `.github/workflows/deploy.yml` drops its Flutter step, which made the company app's build fail on a phone-only import, because the company app no longer builds the page; `mobile-ci.yml`'s `flutter test` runs `test/web_imports_test.dart` on each change to `mobile/`, and `publish-relay-server.mjs` still builds the page before each server deploy.

**2026-11-10** — Assumed: the live check (`app.relayeverything.com/` with no company login, the admin card, a phone sync) runs right after the merge, with the two publish commands, not as a task, because a task must be done before the merge.

**2026-11-10** — Built: every task but the staging check. The review found nothing to fix. Local checks and `flutter test` (685) pass.

**2026-11-10** — Checked on staging (`e96a18f`, headless Chrome; the assistant's own browser draws no Flutter page, live or staging): `/` answers `200` and shows the sign-in; `/?signIn=failed` shows the failure; *Sign in with Google* goes to `sign-in/google?next=%2F`, then to Google; phone connect and AI-app connect, signed out, answer `302` to `/?next=…`; `/apps/relay/` and its files still answer `200`.

**2026-11-10** — Assumed: no full sign-in or phone sync on staging before the merge, because an email code needs the owner's inbox, and the change touches no route a signed-in page or phone calls. The live check after the merge covers a signed-in phone.


**2026-11-10** — Archived for shipping.
