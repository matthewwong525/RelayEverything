# Sign in from the webhook Account page, and keep your webhook

**Status:** in-progress
**Branch:** webhook-login-option
**Open questions:** none

## Why

A phone that sends to your own webhook has no way to sign in. The Account page shows only the webhook, *Notes from elsewhere* and *Stop sending*. To sign in, you must tap *Stop sending*, sign in from Settings, then pick *Only my own webhook* again. Nobody finds that path.

## What Changes

- **A *Sign in to Relay Everything* row on the webhook Account page.** It replaces *Notes from elsewhere*, which told you to sign in but opened the web page. The row says what you get: your notes on your page, your AI and your other phones, while health, places, calendar and photos still go only to your webhook.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹ Settings</button></div>
    <h3>Account</h3>
    <div class="card col gap"><div class="row gap"><div class="col grow"><b>My own webhook</b><span class="muted">db.example.com</span></div><button class="btn-ghost">Send a test</button></div></div>
    <div class="card col gap"><div class="row gap"><div class="col grow"><span>Sign in to Relay Everything</span><span class="muted">Sync your notes with your page, your AI and your other phones. Health, places, calendar and photos still go only to your webhook.</span></div><span class="muted">›</span></div></div>
    <div class="card col gap"><span class="danger">Stop sending</span></div>
  </div>
  ```
- **Signing in keeps your webhook for your private data.** The row opens the same *Sign in* screen as Settings. After you sign in, your notes go to Relay Everything, and health, places, calendar and photos go only to your webhook, as if you picked *Only my own webhook*. The Account page then shows the signed-in page with *Only my own webhook* picked. If you close the sign-in or it fails, nothing changes: the phone still sends everything to your webhook.
  ```mermaid
  flowchart LR
    A["Webhook only"] -->|"Sign in"| B["Notes to Relay Everything"]
    A -->|"Sign in"| C["Private data still to your webhook"]
  ```
- **The phone asks about your earlier notes.** Notes you already sent to your webhook are not in your account. After sign-in, the phone asks *Send your 12 earlier notes too?*, as it does today for notes written while sending was off. *Send them* puts them on your page, your AI and your other phones. *Only new notes* leaves them only at your webhook.
  ```screen
  <div class="card col gap phone">
    <b>Send your 12 earlier notes too?</b>
    <span class="muted">They are not on Relay Everything yet. New notes go to your Relay Everything server from now on.</span>
    <div class="row gap"><span class="grow"/><button class="btn-ghost">Only new notes</button><button class="btn-primary">Send them</button></div>
  </div>
  ```
- **Your webhook stops getting notes from the phone.** Signed in, notes go to Relay Everything. To keep getting notes at your webhook, add it on your Relay Everything page, and the server sends them on. Right after this sign-in, a short message at the bottom of the screen says so.
  ```screen
  <div class="card col gap phone">
    <span class="muted">Signed in. To get your notes at your webhook too, add it under Webhooks on your Relay Everything page.</span>
  </div>
  ```
- **The website says how.** The Settings page explains the new row and what changes after you sign in.

Non-goals: no change to the server or its webhooks; the phone does not add your webhook to your Relay Everything page for you; no change to the signed-out *Sign in* screen.

## What the build needs

- **Nothing.** The phone already signs in, keeps a webhook, and sends private data only to it.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-home-screen`: the webhook Account page offers *Sign in to Relay Everything*; signing in from it keeps the webhook for health, places, calendar and photos, and asks about notes that went only to the webhook.
- `relay-sending`: notes that went only to the person's own webhook count as earlier notes when the phone signs in to Relay Everything.

## Impact

- `mobile/lib/screens/account.dart`: the webhook page's *Sign in to Relay Everything* row replaces *Notes from elsewhere*; the message after sign-in about notes at the webhook.
- `mobile/lib/screens/folder.dart`: `_EarlierDialog` says the notes are not on Relay Everything yet; `choosePlace` gains a way to keep the webhook for private data, so both sign-in paths share one flow.
- `mobile/lib/controller.dart`, `mobile/lib/relay.dart`: `earlierNotes` and `startSending` count and queue own notes that went only to the webhook, when the phone moves from the webhook to a server.
- `mobile/lib/data/store.dart`: an earlier-notes query that includes own notes with no server id.
- Tests: `mobile/test/screens_test.dart`, `controller_test.dart`, `store_test.dart`; the iPhone check's tour if it taps *Notes from elsewhere*.
- Docs: `site/src/content/docs/app/settings.md`, `site/src/content/docs/connections/your-database.md` if it names the old row, `mobile/README.md` if it names it.

## Decision log

- **2026-11-09** — Asked whether a phone sending to its own webhook can sign in → chose to add a way to sign in from the webhook Account page.
- **2026-11-09** — Asked whether notes already sent to the webhook go to Relay Everything after sign-in → chose ask, then send, with the earlier-notes question.
- **2026-11-09** — Assumed: after sign-in, health, places, calendar and photos stay on the webhook (*Only my own webhook*), because the person chose a webhook to keep that data off our server, and the offer they accepted said so.
- **2026-11-09** — Assumed: the new row replaces *Notes from elsewhere*, because that row only told the person to sign in and opened the web page instead.
- **2026-11-09** — Assumed: the phone does not add its webhook to the person's Relay Everything page, because a device key only adds data and never changes account settings; the page tells the person to add it.
- **2026-11-09** — Assumed: no prototype pictures, because the phone app is Flutter and the plan's prototype runs only the web app; widget tests and the iPhone check show the built screens.
- **2026-11-09** — Assumed: plan on the newest main (fe36e36), because this workspace was behind it.
- **2026-11-09** — Assumed: the screens' fake `Relay` lives in `mobile/test/screens_test.dart`, not `test/fakes.dart`, so the build updated it there.
- **2026-11-09** — Assumed: *Send them* for notes that went to the webhook also sends all their files, and drops a change still waiting for such a note, because the server never got either and the new upload carries the newest words.
- **2026-11-09** — Assumed: the Settings sign-in also counts notes that went to the webhook when the phone last sent there, because they are not on the person's space either; the question then says *They are not on Relay Everything yet.*
- **2026-11-09** — Assumed: the sign-in opened from the webhook Account page says health, places, calendar and photos still go only to the webhook, in place of *Notes stay on this phone until you sign in*, which is not true there.
- **2026-11-09** — Assumed, at review: the earlier-notes question says *They are not on Relay Everything yet.* in place of *They went only to your webhook.*, because the count may also hold notes that never left the phone, and the new words are true for both.
- **2026-11-09** — Saved for final acceptance: built, and a second review found one gap, fixed: the earlier-notes question could say notes went to the webhook when some never left the phone. `flutter analyze` is clean and all 574 phone tests pass. The iPhone device check (4.2) runs on this saved commit.
