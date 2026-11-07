# Send from the phone straight to your own webhook

**Status:** ready-to-ship
**Branch:** phone-app-webhook-infrastructure
**Open questions:** none

## Why

Today a webhook works only when your data first goes to a Relay Everything server. Some people want their notes, health and places to go to their own database and never touch our server. The phone can send to their webhook itself, in the same signed format the server uses, so one receiver works for both.

## What Changes

- **You pick where the phone sends: Relay Everything or your own webhook, never both.** The phone keeps one list of what waits to send, in order, as it does today. Only the place at the end changes.
  ```mermaid
  flowchart TD
    N["Notes, health, places"] --> L["The phone's waiting list"]
    L -->|"Relay Everything"| S["Our server"]
    L -->|"Your own webhook"| W["Your receiver"]
  ```
- **Settings says where the phone sends.** *Send to Relay Everything* becomes *Send my notes*, with a line under it that names the place. Turning it on asks which place you want.
  ```screen
  <div class="row gap">
    <div class="card col gap phone">
      <span class="muted">Before</span>
      <h3>Settings</h3>
      <div class="row gap"><span class="grow">Send to Relay Everything</span><span class="tag">On</span></div>
      <span class="muted">Your server can pass notes to your own database and your AI.</span>
      <div class="row gap"><span class="grow">Server</span><span class="muted">app.relayeverything.com</span></div>
    </div>
    <div class="card col gap phone">
      <span class="muted">After</span>
      <h3>Settings</h3>
      <div class="row gap"><span class="grow">Send my notes</span><span class="tag">On</span></div>
      <span class="muted">To your webhook: db.example.com. Nothing goes to Relay Everything.</span>
      <div class="row gap"><span class="grow">Webhook</span><span class="muted">https://db.example.com/relay</span></div>
      <button class="btn-ghost">Send a test</button>
    </div>
  </div>
  ```
  These are sketches, not pictures: the plan's prototype runs only the web app, not the phone app.
- **Set up your webhook on the phone, with no account.** You need no Relay Everything account, sign-in or key: only your receiver's address and its secret. You type your receiver's address and get a secret to copy. *Send a test* shows your receiver's answer at once. The address must start with `https://`. A home address, such as your own computer on your Wi-Fi, is allowed.
  ```screen
  <div class="card col gap phone">
    <h3>Where should the phone send?</h3>
    <div class="row gap"><span class="tag-outline">Relay Everything</span><span class="tag">My own webhook</span></div>
    <div class="field col gap"><span class="muted">Address</span><span>https://db.example.com/relay</span></div>
    <div class="field col gap"><span class="muted">Secret</span><span>whsec_…</span></div>
    <span class="muted">Copy the secret to your receiver. It checks each message with it.</span>
    <div class="row gap"><button class="btn-ghost">Copy</button><button class="btn-ghost">Send a test</button><span class="grow"></span><button class="btn-primary">Save</button></div>
  </div>
  ```
- **Your receiver gets the same messages as from the server**, signed the same way: new notes, health and places. One new kind of message carries each file on a note, so your files reach your receiver too. A file goes after its note.
  | Message | From the phone | From the server |
  | --- | --- | --- |
  | A new note | Yes | Yes |
  | Health, places | Yes, if you turn them on | Yes, if you tick them |
  | A note's file | Yes, one message for each file | No, a list of names only |
- **What you give up with your own webhook.** The phone sends only while it is on and has signal, so data comes in groups, not live. Your Relay Everything page and your AI can't read it, because none of it is on the server. Settings and the website say this in plain words.
- **The website explains it.** The Settings, privacy and *Your own database* pages say how to send from the phone, what each message holds, and what you give up. The example receiver also saves files.

Non-goals: sending to Relay Everything and a webhook at the same time; more than one webhook on the phone; changing the server's own webhooks; a home receiver with a self-made certificate.

## What the build needs

- **Nothing.**

The build starts after *Share to Relay Everything* is live, because both change the same phone files. The phone already has the code it needs to sign messages.

## Capabilities

### New Capabilities
- `relay-phone-webhook`: the phone sends notes, files, health and places straight to one webhook the person sets on the phone, signed in format v1, as an alternative to the server.

### Modified Capabilities
- `relay-sending`: sending has two places, the server or the person's own webhook, never both; the offline default, the earlier-notes question and turning off apply to both.
- `relay-webhooks`: format v1 gains a `note.file` message that only the phone sends; the published schema and example receiver include it.

## Impact

- **Phone app** (`mobile/lib/`): `data/settings.dart` (where to send), `data/sender.dart` and a new `data/webhook.dart` (a signed webhook client beside `RelayApi`), `data/outbox.dart` (`flush` sends by the item's `destination`), `data/store.dart` (switching moves waiting items), `screens/settings.dart`, `screens/connect.dart`, `controller.dart`, `sync/background.dart`; the share sheet's Swift files after *Share to Relay Everything*.
- **Format** (`app/worker/apps/relay/webhooks/format.ts`): adds `note.file`; `npm run relay:api-doc` rewrites `site/public/webhooks/v1.schema.json`. The server never sends the new type.
- **Website** (`site/`): `app/settings.md`, `connections/your-database.md`, `privacy.md`, `start/connect-a-phone.md`, `public/webhooks/receiver.mjs`.
- **Wiki**: `wiki/relay-spaces.md` *Webhooks* links the phone's path.

## Decision log

- **2026-11-07** — Asked whether the phone should send to the server or a webhook by the same system → chose the phone sends straight to a webhook so data skips our server.
- **2026-11-07** — Asked whether to allow several webhooks on the phone → chose one webhook.
- **2026-11-07** — Asked whether the phone may send to both places → chose one or the other, never both, through the one sender and the one waiting list.
- **2026-11-07** — Asked whether webhook mode sends each file's contents → chose send each file, as its own message after its note.
- **2026-11-07** — Asked when to build, as *Share to Relay Everything* changes the same files → chose plan now, build after it is live.
- **2026-11-07** — Asked whether webhook mode needs a sign-in → chose no: no Relay Everything account, sign-in or key, only the address and secret.
- **2026-11-07** — Assumed: the phone sends format v1, signed by Standard Webhooks, because one receiver then works for the server and the phone.
- **2026-11-07** — Assumed: the phone makes the secret and shows it with *Copy*, and the person can paste their own, because the server's webhooks work the same way.
- **2026-11-07** — Assumed: the address must be `https://`, but a home or private address is allowed, because the server blocks those only to protect itself, and the person's own phone needs no such guard.
- **2026-11-07** — Assumed: only a 2xx answer counts as sent; any other answer keeps the item and stops the round, except a 413 on a file, which drops that file, because a receiver error must not lose data and one too-large file must not hold back the rest.
- **2026-11-07** — Assumed: switching the place moves every waiting item to the new place, because the person chose one place.
- **2026-11-07** — Asked whether the plan covers the Pebble app sending to the server → chose to leave it out: that path is no longer used.
- **2026-11-07** — Assumed: the plan's test gates move to the end of the build, with their acceptance kept, because the build writes all source and tests first.
- **2026-11-07** — Assumed: turning on *Send my notes* always opens *Where should the phone send?*; with a key kept it offers *Send to Relay Everything* at once, because the person picks the place each time.
- **2026-11-07** — Assumed: Settings gets a *Where the phone sends* row while sending is on, to switch places, because a switch must not need sending off first.
- **2026-11-07** — Assumed: in webhook mode the iPhone share card gets a second App Group key, `later`, and says *Kept. It sends when you open Relay Everything.*, because *Sending is off* would be wrong.
- **2026-11-07** — Assumed: the device name is *iPhone* or *Android phone*, because the app reads no phone model.
- **2026-11-07** — Assumed: a note's `created_at` and each message's `timestamp` are when the phone queued the item, because the phone has no server store time.
- **2026-11-07** — Assumed: the phone keeps health and point ids in each waiting body and strips them before it sends to the server, because the server's routes refuse unknown fields.
- **2026-11-07** — Assumed: one round sends through one client and stops at an item for the other place, so a switch in the middle of a round sends nothing to the place left.
- **2026-11-07** — Assumed: a *too large for your receiver* line stays in Settings until the next failure, a new webhook, or a 2xx with no file named, so the person sees which file was dropped.
- **2026-11-07** — Assumed: the example receiver and the Postgres tables key samples and points by device id and id, because the phone numbers its own from 1 and they would replace the server's rows.
- **2026-11-07** — Assumed: flush tests for both places live in `webhook_test.dart` and `data_test.dart`, because the app has no `outbox_test.dart`.
- **2026-11-07** — Assumed: task 6.2 ran the phone's own sending code (`flush` with `WebhookClient`, from a throwaway `flutter test`) against the example receiver behind a temporary `https://` tunnel, not a phone build, because this computer has no phone or emulator; the receiver checked every signature and kept the note, its 2,048-byte file, a health sample and a location point. The iPhone device check in `/verify` covers the phone build.
- **2026-11-07** — Assumed: built on top of *Share to Relay Everything* after it went live (#35), so the share sheet keeps items for the app in webhook mode.
- **2026-11-07** — Check: `scripts/public-check.test.mjs` now checks that `--notes` never prints `555-0134`, not `555`, because the output names a random commit id that sometimes holds `555` and failed main's checks after #37; the phone number is still never printed.
- **2026-11-07** — Archived for publishing. Main gained the Pebble removal (#37) meanwhile; the merge keeps this change's *Send my notes* screens and texts without the Pebble lines, and `device` now reads *the phone or other device*.
- **2026-11-07** — Assumed: after main gained the phone's calendar and more health (#36), webhook mode sends calendar events too, as `calendar.events`, because everything else the phone sends goes to the one place the person picks, and an unknown upload would stop the round. The phone has no server id for an event, so an event's `id` is the first 48 bits of the SHA-256 of the install id and its key: each change of one occurrence keeps its id, and a receiver upserts by it. A removed event carries only its key, id and start. A switch of place forgets what of the calendar went, so the next read sends the whole window to the new place. The iPhone device check before this merge ran out of time before Claude's verdict (could-not-check); its pictures showed the place choice, the refused `http://` address and no sign-in for the webhook, with nothing against the plan.
