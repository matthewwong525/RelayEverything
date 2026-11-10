# One simple Settings on the phone and the web, with developer options under Advanced

**Status:** built, saving
**Branch:** simpler-settings-match-mobile-web
**Open questions:** none

## Why

Settings on the phone and Settings on the web do not match. The same thing has a different name and place on each. The phone's Account page does too many jobs, and it asks where your health, places, calendar and photos go. Most people never need that choice. Sign in also shows five ways in. The default must be simple: you sign in, turn things on, and your data goes to Relay Everything.

## What Changes

These pictures come from a test copy of the app, built on the plugin change, with real fonts and sample data.

- **Settings is the same on the phone and the web.** Both show your account first, then *Appearance*. The phone also keeps *Notes* and *Voice notes*, which only a phone can do, and the version number. On the web, Settings lists only *Account* and *Appearance*. Settings has no *Advanced* row: the developer options sit at the bottom of Account.
  ```picture
  Before, phone: pictures/before-settings.png
  After, phone: pictures/after-settings.png
  Before, web: pictures/before-web-settings.png
  After, web: pictures/after-web-settings.png
  ```
- **Account holds you, your phones, and an Advanced part at the bottom.** The account card shows your email, *Signed in*, and *Sign out* beside it, as on the web today. *Phones* lists your phones by name, this phone marked, each other phone with *Sign out*: you sign out a lost or sold phone here. *Advanced* holds the developer options: *Webhooks*, and on the web *API keys*. *Delete my account* comes last, alone, in red; on the phone it opens your page.
  ```picture
  Before, phone: pictures/before-account.png
  After, phone: pictures/after-account.png
  After, web: pictures/after-web-settings.png
  ```
- **Other connections holds Connect your AI and Email notes, each with one line that says what it does.** On the phone, *Other connections* on Home has the two rows; on the web, the left bar has the same rows, and each opens in the main pane. **Connect your AI** (*Let your AI read your notes*) has two parts. *Claude Code and Codex* lists the computers with the plugin, with when each last saved a chat, then *Saved chats* (only the plugin saves your chats) and *Get the plugin*. *Claude, ChatGPT and other AI apps* shows the address to copy and each connected app with the day it connected. On the web you disconnect a computer or an app there; on the phone, that opens your page. The *AI chat transcripts* row goes: your saved chats open from *Connect your AI*. **Email notes** (*Email a note to your own address*) shows two addresses, each with *Copy*: `notes@in.relayeverything.com`, which takes mail only from the email you sign in with, and your private address, which takes mail from anyone, for a forward rule. *New address* stays on the web.
  ```picture
  Before, Home: pictures/before-home.png
  After, Home: pictures/after-home.png
  After, Connect your AI: pictures/after-connect-ai.png
  After, Email notes: pictures/after-email-notes.png
  ```
- **Sign in has one button and one link.** *Sign in* is the one button. Below it, *Don't want an account? Use your own webhook* opens the webhook setup in four short steps: paste your address, copy the secret to your receiver, send a test, save. The phone no longer offers a QR code, a pasted key or another server: it signs in only to Relay Everything. Once a webhook is saved, the account card says *My own webhook*, and its page shows the address, *Send a test*, *Sign in to Relay Everything* and *Stop sending*.
  ```picture
  Before: pictures/before-sign-in.png
  After: pictures/after-sign-in.png
  After, no account: pictures/after-webhook.png
  ```
- **Everything goes to Relay Everything unless you change it in Webhooks.** The Account page no longer asks where your health, places, calendar and photos go, and the account card says only *Signed in*. On the phone, *Webhooks* (Account, Advanced) lists your webhooks by name, opens your page to add or change one, and holds *Only to my own webhook* for health, places, calendar and photos. On the web, *Webhooks* adds and changes them as today, and *API keys* makes a key for your own scripts. If you already send private data to your own webhook, nothing changes for you.
  ```picture
  After, phone: pictures/after-webhooks.png
  ```
- **Gray buttons show their words again.** Today a gray button, such as *Copy* or *Sign out*, can draw its words as black boxes when its font has not loaded. The fix gives these buttons the app's font.

Non-goals: no new data on the web's Location, Health, Calendar and Photos pages; no change to what the phone sends or how; no change to the plugin or the AI connector.

## What the build needs

- **Nothing.** The build waits only for the plugin change, *One Relay Everything plugin for Claude Code and Codex*, to go live from its own chat, because it also changes *Other connections*.

## Capabilities

### New Capabilities

- `relay-settings`: one Settings shape on the phone and the web: the account card, Account with Phones, Advanced and Delete, Appearance, and Sign in with one button and the no-account webhook.

### Modified Capabilities

- `relay-home-screen`: *Other connections* holds *Connect your AI* (with the plugin's computers and saved chats) and *Email notes*; Settings and the Account page move to `relay-settings`.
- `relay-web-app`: the left bar holds *Connect your AI* and *Email notes*, and no *AI chat transcripts* row; the Settings dialog lists Account and Appearance.
- `relay-sending`: the private-data choice moves to Webhooks under Account; the phone signs in only to Relay Everything, or sends to its own webhook with no account.
- `relay-phone-webhook`: the person sets the phone's webhook in four steps, from the sign-in with no account or from Webhooks while signed in.
- `relay-device-keys`: a phone key also reads its person's device names and notes addresses, and signs out one of its person's phones; the web's *Add a device* becomes *Add an API key*, with no phone QR code.

## Impact

- Phone and web screens in `mobile/lib/screens/` (`settings.dart`, `account.dart`, `connect.dart`, `home.dart`, `connected_names.dart`, `transcripts.dart`) and `mobile/lib/web/` (`settings_dialog.dart`, `shell.dart`, `ai_apps_page.dart`, `email_notes_page.dart`, `devices_page.dart`, `webhooks_page.dart`).
- `GET connections` in `app/worker/apps/relay/connections.ts` adds devices, both notes addresses and each AI app's connect day; `POST devices/off` lets a phone key sign out a phone; `npm run relay:api-doc` reruns.
- `AGENTS.md` *Device keys* and *offline by default* lines, `app/self-host/SETUP.md`, and the website pages under `site/src/content/docs/` that name Settings, Devices, *Add a device*, *Scan a key*, *Use another server* or the webhook choice.
- Flutter widget tests in `mobile/test/`, server tests for `GET connections` and `POST devices/off`, and the iPhone device check's tour.

## Decision log

- **2026-11-10** — Asked whether phone rows for AI apps, Devices, Webhooks and Email notes should manage things or only show them → chose to put them under *Other connections*, each with a line that says what it does, and keep AI chat transcripts as its own row.
- **2026-11-10** — Asked whether Webhooks go under Advanced → chose yes, on the phone and the web.
- **2026-11-10** — Asked how hidden Advanced is → chose a visible *Advanced* row at the bottom of Settings.
- **2026-11-10** — Asked how the two AI rows show → chose two rows, *Connect your AI* and *AI chat transcripts*, each explained.
- **2026-11-10** — Asked where Devices goes → chose inside Account.
- **2026-11-10** — Asked (when reviewing) why the phone needs Devices and Connect your AI → kept *Connect your AI*, which tells a phone-first person their AI can read their notes; replaced the device list on Account with *Sign out of all devices*, which the person proposed, on the phone and the web, and moved the list and API keys to *Advanced* on the web, because a phone or computer gets its key by signing in, so only a lost device or a script needs the list.
- **2026-11-10** — Asked (in a message during planning) that a person who wants no account but a webhook finds it easily → the sign-in keeps *No account? Use your own webhook* as a second quiet link, and only the signed-in private-data choice moves to Advanced.
- **2026-11-10** — Asked when to start, since the plugin change also edits *Other connections* → chose to plan now and build after it ships.
- **2026-11-10** — Asked why each computer has its own key and whether devices can share one → explained that the server keeps each device's notes, calendar, places and chats apart by its key, so phones and computers keep one key each and never show it, and that one API key can serve many scripts.
- **2026-11-10** — Asked where each item goes on Account and Advanced → chose one rule: Account is you and the safety actions everyone needs (*Sign out*, *Sign out of all devices*, *Delete my account*); *Other connections* is what reads or adds to your notes; *Advanced* is for developers: on the web *Devices* (sign out one), *API keys* and *Webhooks*; on the phone *Webhooks*, the private-data choice and *Server*. A device row says *Sign out*, not *Turn off*.
- **2026-11-10** — Assumed: the phone shows AI apps, computers and webhooks by name and opens the web page to change them, because a phone key that can add an AI app makes a lost phone more dangerous.
- **2026-11-10** — Assumed: a person who already sends private data to their own webhook keeps that setting, because changing where private data goes without asking breaks their trust.
- **2026-11-10** — Assumed: old web links to `#ai-apps`, `#email-notes`, `#chats`, `#devices` and `#webhooks` open the new place, because the phone and the docs link to them.
- **2026-11-10** — Assumed: the web keeps Location, Health, Calendar and Photos under *Other connections* in its left bar, above the new rows, because the person picked that name for the web on 2026-11-10 and the browser has no *On this phone*.
- **2026-11-10** — Asked (in a message during planning) why the plan showed wireframes, not the real app → the plan now shows real pictures, made by screenshot tests in a test copy of the app built on the plugin change.
- **2026-11-10** — Assumed: the plan fixes the gray buttons' font, because the screenshot tests showed *Copy* and *Sign out* drawn as black boxes when the font had not loaded.
- **2026-11-10** — Asked (review notes) for fewer sign-out buttons on Account, maybe grouped like connections → chose the account card with *Sign out* beside it, a *Phones* list with *Sign out* on each other phone, and *Delete my account* alone at the bottom; *Sign out of all devices* goes.
- **2026-11-10** — Asked (review notes) whether Webhooks and the private-data choice belong under Account → chose an *Advanced* part at the bottom of the Account page, which the person proposed, in place of an *Advanced* row in Settings; the private-data choice moves inside *Webhooks*.
- **2026-11-10** — Asked (review notes) how a person knows an AI is connected, and to include the plugin and fold in AI chat transcripts → *Connect your AI* shows the plugin's computers with their last saved chat, *Saved chats*, and each AI app with its connect day; the *AI chat transcripts* row goes.
- **2026-11-10** — Asked (review notes) to show the email address that takes mail only from the person's own email → *Email notes* shows `notes@` (only from the sign-in email) and the private address (from anyone).
- **2026-11-10** — Asked (review notes) to drop other ways to sign in, a QR code and other servers → the phone signs in only to Relay Everything, with no QR code, pasted key or *Server*; the web makes no phone QR code; the link reads *Don't want an account? Use your own webhook*.
- **2026-11-10** — Asked (review notes) whether the plugin uses an API key or the AI connector → explained that the plugin connects each computer with its own sign-in and reads through a small command, not the AI connector, so no connector tools load; API keys are only for the person's own scripts.
- **2026-11-10** — Asked (review notes) to cut the account card's text → the card says only your email and *Signed in*; the private-data choice shows in *Webhooks*.
- **2026-11-10** — Assumed: computers move to *Connect your AI* and Account lists only phones, because a computer connects through the plugin, and its saved chats live there.
- **2026-11-10** — Assumed: a phone key may sign out another of its person's phones but not a computer, an API key, an AI app or a webhook, because Account on the phone lists only phones, and the worst a thief can do is make the person sign in again.
- **2026-11-10** — Assumed: a phone already signed in to another server keeps working, and a self-hosted server's people use the web app and the plugin, because the person said other servers are not needed for now.
- **2026-11-10** — Assumed (build): `GET connections` also gives `thisDevice`, the phone's own device id, because the phone marks itself *This phone* and offers no *Sign out* beside itself.
- **2026-11-10** — Assumed (build): a font check replaces the planned golden test of *Copy* and *Sign out*. The test loads Inter and checks that each quiet button draws its words in Inter, because a pixel golden differs between macOS and Linux runners.
- **2026-11-10** — Assumed (build): old web parts open their new place. `#chats` and `#ai-apps` open *Connect your AI*, `#email-notes` *Email notes*, `#devices` Account and `#webhooks` Webhooks. A new `#saved-chats` opens the saved chats, and the phone's *Read them on the web* uses it. `#api-keys` opens API keys.
- **2026-11-10** — Assumed (build): the phone's *Saved chats* opens the app's own steps page, now named *Saved chats*. *Get the plugin* opens the website's plugin guide. The page shows no chat count, because the phone reads no chats.
- **2026-11-10** — Assumed (build): the phone shows the AI connector's address only when signed out or signed in to Relay Everything's own server. Signed in to another server, it says to find the address on that server's page, because only Relay Everything's server uses `mcp.relayeverything.com`.
- **2026-11-10** — Assumed (build): the web's *Email notes* row is always in the left bar, and its page says when the server takes no email, so the left bar does not change after it loads.
- **2026-11-10** — Assumed (build): the phone's *Delete my account* opens `/#account` on the person's Relay Everything page, where the web asks for the email again.
- **2026-11-10** — Assumed (build): *Sign in* goes to Relay Everything's own server, and a phone that keeps a key for another server still sends there through the kept-key screen. `Relay.connect(code)` stays in the code for that kept key.
- **2026-11-10** — Assumed (build): the app drops `mobile_scanner`, `qr_flutter` and the camera permissions, because nothing scans or shows a QR code any more; `flutter pub get --offline` removed them with no other version change.
- **2026-11-10** — Assumed (build): the phone's Account page has no *Open your Relay Everything page* row; *Delete my account* and the Webhooks page's link open the page where it is needed.
- **2026-11-10** — Timing (build): the test gates of each task, and task 1.1's `flutter analyze` before any edit, ran once at the end, after all source and tests were written.
- **2026-11-10** — Assumed: the plugin's words that sent people to *Devices* now name *Connect your AI*, because the Devices page is gone; the plugin's behavior does not change.
