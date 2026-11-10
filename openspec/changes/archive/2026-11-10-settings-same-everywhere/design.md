# Design

## Context

See proposal.md, Why. The phone and the web app are one Flutter code base: phone screens in `mobile/lib/screens/`, browser-only screens in `mobile/lib/web/`, and `Relay.web` hides phone-only rows. Today:

- The phone's `SettingsScreen` (`screens/settings.dart`) shows `_AccountRow`, Appearance, Notes, Voice notes and the version. `AccountPage` (`screens/account.dart`) holds email, server, AI apps and Webhooks names (`connected_names.dart`, read through `GET connections`), the private-data radio (`SendPlace.server` / `SendPlace.webhook` on `Settings.privateTo`), *Open your page*, Server and Sign out.
- `ConnectScreen` (`screens/connect.dart`) shows *Sign in to connect*, *Scan a key*, *Use another server*, *Send to my own webhook instead*, and a paste field, with `privateOnly` and `signInOnly` modes.
- The web's `showSettingsDialog` (`web/settings_dialog.dart`) lists `SettingsPage` Account, Devices, Webhooks, AI apps, Email notes, Appearance, each reachable by `#part`.
- The plugin change (agent-plugin-and-mcp-address) adds `HomeScreen.otherConnections` rows on the phone, `screens/transcripts.dart`, and renames the web's chats row. This change builds on it once it is on `main`.

## Goals / Non-Goals

**Goals:** one list of Settings rows shared by both shells; Account with the person's phones and an *Advanced* part; Connect your AI and Email notes as connection pages on both, saying what is connected; sign-in with one button and one link; the private-data choice inside Webhooks with no change to how sending works.

**Non-Goals:** no change to `Sender`, the outbox, `privateTo` storage or webhook signing; no change to the plugin or the AI connector; no web view of health or places.

## Decisions

- **One shared description of the Settings rows.** A small list in `screens/settings.dart` names each row (account, appearance, notes, voice, version) with a `phoneOnly` flag. The phone's `SettingsScreen` and the web's `SettingsView` both build from it, so a row added later shows on both or is marked phone-only on purpose. Settings has no Advanced row. Alternative: keep two hand-written lists and a test that compares them; rejected, because the list is the thing that drifted.
- **Account: the card, Phones, Advanced, Delete.** The card is email, *Signed in* and *Sign out* (quiet, trailing). *Phones* lists `relay_devices` rows with `reaches` phone; the row matching the caller's own key says *This phone*, the others have *Sign out*, which calls `POST devices/off` after a confirm. *Advanced* has `FolderRow`s: *Webhooks* on both, *API keys* on the web. *Delete my account* is last; the phone opens the page. Computers do not show here: they show in Connect your AI. Alternative: a sign-out-all button; rejected by the person, a list lets them stop only the lost phone.
- **A phone key may call `POST devices/off` for a phone only.** `device.ts` moves `devices/off` to `asPersonOrPhone`; with a phone key it checks the target is in the same space and has `reaches` phone, else 403. The session keeps full reach. A lost phone can then only sign out the person's other phones, who sign in again.
- **`GET connections` grows, not a new route.** It adds `devices` (`[{id, name, kind, since, lastChatAt}]`, phones and computers, no `api` rows and no key), `notesAddress` (the private inbox address or null), `sharedAddress` (`notes@` + `RELAY_INBOX_MAIL_DOMAIN`, or null when email is off) and `connectedAt` on each AI app. `lastChatAt` is the newest `relay_chats.last_at` for that device. It stays `asPersonOrPhone`, read-only.
- **Connect your AI and Email notes are shared pages with two data sources.** `screens/connect_ai.dart` and `screens/email_notes.dart` render from a small model. Connect your AI: *Claude Code and Codex* (computers with their last chat, *Saved chats* opening the existing `transcripts.dart` view, *Get the plugin*), then *Claude, ChatGPT and other AI apps* (the public address `https://mcp.relayeverything.com`, apps with `connectedAt`). Email notes: the shared address, said to take mail only from the sign-in email, then the private address, said to take mail from anyone. On the web they read `devices`, `ai-apps` and `inbox` through `SpaceClient` and keep *Disconnect* and *New address*; on the phone they read `GET connections` and open the page to change anything. The web's `ai_apps_page.dart` and `email_notes_page.dart` fold into these; the *AI chat transcripts* row on Home and in the left bar goes.
- **Webhooks, one page per shell.** Phone `WebhooksPage`: a muted line, webhook names from `GET connections`, a link that opens `/#webhooks`, and, signed in, the *Only to my own webhook* switch. The switch is the existing `privateTo` flow: on with no webhook opens `ConnectScreen(privateOnly: true)`; off sends waiting private data to Relay Everything as today. A switch replaces the radio pair because off is the default. Web: the existing `webhooks_page.dart`. *API keys*: `devices_page.dart` filtered to `reaches` api, with `AddDeviceDialog` fixed to `api`; the kind picker and the phone QR code go.
- **Sign-in: one button, one link.** `ConnectScreen._server()` shows *Sign in* and one `_quiet` link, *Don't want an account? Use your own webhook*, which opens `_webhook()`. `_scan`, `_ScanPage`, the paste field and the server field go; a saved non-default server keeps working. `_webhook()` is laid out as four numbered steps; its logic is unchanged.
- **Old `#parts` keep working.** `SettingsPage.ofPart` maps `account`, `devices` → Account; `webhooks` → Account's Webhooks; `appearance`. `ai-apps` and `chats` open Connect your AI, `email-notes` Email notes, in the main pane.

## Risks / Trade-offs

- [The plugin change lands with different `otherConnections` code] → the build starts from `main` after it ships and reads that code first; task 1.1 checks it.
- [A phone key reading device names and both addresses widens what a lost phone shows] → names, dates and addresses only, no key or secret; the AGENTS.md *Device keys* line and the device-keys spec say so.
- [A thief with an unlocked phone signs out the person's other phones] → nothing is deleted; each phone signs in again. A computer, an API key, an AI app and a webhook stay out of reach.
- [No *Use another server* on the phone] → a self-hosted server's people use the web app and the plugin, and a phone already set to one keeps it; `SETUP.md` and the site say so. Trying a preview on a phone uses the preview's web app instead.
- [People who used *Only my own webhook* look for it on Account] → it is on Account, under *Advanced*, in *Webhooks*.
- [The device check's tour taps *Sign in to connect*, *Scan a key* and *Send to my own webhook instead*] → the tour's flows are updated in the same change.

## Migration Plan

No data moves. Ship the server first (the phone reads the new fields only when present), then the web app and the phone build; an older phone ignores the new fields. Rollback is a revert.

## UX

### Use-case brief

- **Who:** a person using Relay Everything on their phone and in a browser; sometimes a developer with their own server or webhook.
- **The job:** check you are signed in and change a look or a device, without meeting choices you don't understand. A developer: send data to their own receiver, with or without an account.
- **Done looks like:** signed in, everything on goes to Relay Everything, and Settings looks the same in both places.
- **Context of use:** the phone first, one hand; the web at a desk in the Settings dialog.
- **Common case:** open Settings, see you are signed in, change Appearance; set up once with *Sign in*. **Edge cases:** a lost phone (Account, Phones, *Sign out*), no-account webhook (one quiet link on the sign-in), private data only to a webhook (Account, Advanced, Webhooks).
- **Frequency (assumed):** a person opens Settings a few times a month; a developer opens Webhooks once at setup.
- **Closest screens:** iPhone Settings (Apple Account card first, *Developer* near the bottom) and the current phone `SettingsScreen`.

### Flow

Signed out: Settings → account card → *Sign in* → done. No account: Sign in → *Don't want an account? Use your own webhook* → address, copy secret, test, Save → done. Lost phone: Settings → Account → Phones → *Sign out* → confirm. Private data to a webhook: Settings → Account → Webhooks → switch → webhook setup → Save. AI: Home → Connect your AI → see the laptop and Claude, or copy the address.

### Hierarchy

- Settings: no filled button; the account card is the strongest row.
- Account: no filled button; *Sign out* quiet beside the email and on each other phone; *Delete my account* in red, alone and last.
- Sign in: *Sign in* is the one filled button; both links quiet.
- Webhook setup: *Save* is the one filled button.
- Webhooks: a muted line that it is for developers; no filled button.
- Connect your AI and Email notes: *Copy* is the one action.

### Review

[review.html](review.html). What Changes pictures, from screenshot tests in a test copy of the app: *Settings is the same on the phone and the web* (Settings, both shells), *Account holds you, your phones, and an Advanced part* (Account, both shells), *Other connections holds Connect your AI and Email notes* (Home, Connect your AI, Email notes), *Sign in has one button and one link* (Sign in and webhook setup), *Everything goes to Relay Everything unless you change it in Webhooks* (the phone's Webhooks).

### Components

Existing: `Group`, `FolderRow`, `SwitchListTile`, `ListTile`, `BackTo`, `SliverAppBar.large`, `quietButton`, `CopyField`, `SettingsBody`, `SpaceView`. New: `WebhooksPage` on the phone, and `ConnectAiPage` and `EmailNotesPage`, shared by both shells, each built from these parts.
