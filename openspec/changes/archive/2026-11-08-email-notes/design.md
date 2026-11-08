# Design

## Context

Notes reach a person's space today through device keys (`caller.ts` `asDevice`), the web API and the AI connector. Each route opens only its caller's space through `spaceOf` ([the one-door rule](../../../wiki/relay-spaces.md#the-one-door-rule)). `add-note.ts` stores a typed note and its file list once per device and `clientId`, then wakes the webhooks. `attachments.ts` seals files with the space's own key, up to `MAX_FILE_BYTES` (25 MB) each.

Email differs in one way. Mail from Cloudflare Email Routing carries no Relay Everything key, so the server must find the person from the address or the sender. That needs a directory lookup in D1 before a space opens, the same as sign-in finds a person from an email.

The shared server is `worker/relay-only.ts` at `app.relayeverything.com` (`wrangler.relay.jsonc`). It already sends sign-in mail through Cloudflare's `send_email`. A self-host runs the same Worker. The apex `relayeverything.com` already has Email Routing MX records for `matt@`; `in.` is a separate subdomain with its own MX records, so the two never mix.

## Goals / Non-Goals

**Goals:**

- One inbox function that email calls with one item shape (person, channel, sender, message id, text, files), so a later way in reuses it.
- A person found only from a secret address or a checked sign-in email. No route takes a person id from the request.
- Email off until its mail domain is set, so a self-host works with none.

**Non-Goals:**

- Text messages, WhatsApp and Telegram. The Telnyx number +1 833 865 4321 stays bought for later; this change builds nothing for it.
- Sending any mail back.
- Reading the person's mailbox. Only mail sent to a notes address counts.
- Voice to words. An emailed audio file is kept as a file.

## Decisions

### One inbox function, reached only after a checked lookup

`inbox/receive.ts` exports `receive(env, link, item)`. `link` comes only from `inbox/links.ts`, which looks up `relay_inbox_links` by channel and an HMAC-SHA-256 under `RELAY_INBOX_HMAC_KEY`, or the directory's sign-in email for `notes@`. It then calls `vouch("inbox", personId, { device })` to open the space. `space-access.test.ts` adds `inbox/links.ts` to the files that may call `vouch`.

`receive` stores the files, calls `addNote` with `clientId = "email:<Message-ID hash>"` so a repeat stores once, and returns. Considered and rejected: an `email()` handler that writes notes itself. A later way in would copy the store logic, and copies drift apart.

### Email is a device in the space

The first mail makes an `inbox` device row in the person's space, named *Email*. Notes keep `source = 'typed'` and point at that device, so the timeline, webhooks and connector show where a note came from with no new note column. Migration `0007_inbox.sql` widens `relay_devices.reaches` to add `inbox`, with the same copy, drop, make-again pattern as `0003` and `PRAGMA defer_foreign_keys = ON` ([space migrations](../../../wiki/relay-spaces.md#space-migrations)). An `inbox` device has no key, so `caller.ts` gives `inbox` no routes.

### A secret address for each person, and one shared address

Each person gets `notes-<10 random base32>@<RELAY_INBOX_MAIL_DOMAIN>`, kept in D1 as `relay_inbox_links (channel, sender_hmac, person_id, shown, created_at, PRIMARY KEY (channel, sender_hmac))` with `channel = 'email'` and `sender_hmac` = HMAC of the local part. The HMAC keys the lookup; `shown` holds the local part in plain text so the card can show it, and is never logged. The mail domain is public, so a copy of the directory gives every address: *New address* is the remedy for a leak. *New address* deletes the old row and makes a new one. Cloudflare Email Routing sends every mail for the mail domain (a catch-all) to the server's `email()` handler.

- **A person's secret address:** any mail becomes a note, whoever sent it. The address is the secret.
- **`notes@<mail domain>`:** counts only when the `Authentication-Results` header that Cloudflare adds shows `dmarc=pass`, or `spf=pass` and `dkim=pass` aligned to the `From` domain. A `From` that is a sign-in email becomes a note in that space. Any other checked `From` is kept. Mail that fails is dropped.
- **Any other address** is dropped with `message.setReject`, so the sender's server reports it.

Mail is parsed with `postal-mime`: the subject, then the plain text cut at a reply quote (or the HTML turned to text when there is no plain part), then attachments up to 10 files of 25 MB. Bigger or extra files are left out, and the note names them. A part the body shows by its Content-ID (`multipart/related`) counts as a file from 20 KB, such as a pasted screenshot; a smaller one, such as a logo or a tracking pixel, is skipped and not named.

### Kept mail from emails with no account

Mail to `notes@` from a checked email with no account goes to D1 `relay_inbox_held (id, channel, sender_hmac, sent_at, body, created_at)`, with its files in the bucket under `held/<sender_hmac>/<id>`. Each one is sealed with AES-256-GCM under a key made by HKDF from `RELAY_INBOX_HMAC_KEY` and the lowercased sender email. The server stores only the HMAC, so a copy of the database and bucket alone can't open kept mail. Each email keeps at most 100 messages and 50 MB, the oldest going first.

Each sign-in by email code, Apple or Google claims held mail for the person's email in `waitUntil`, after a lookup by the sender HMAC finds rows waiting: it opens each row, passes it to `receive` in time order with its first `sent_at`, seals its files again with the space's own key, and deletes the held row and objects. `clientId` keeps a claim that runs twice from storing twice, so a claim that stops partway finishes at a later sign-in, before the 30-day sweep.

A daily Cron Trigger on the shared server deletes held rows and objects older than 30 days. It walks only `relay_inbox_held` and the `held/` prefix, never a space.

### Email turns on by its mail domain

`GET /apps/relay/api/inbox` returns `{ email: { on, address, shared } }`. Email is `on` when `RELAY_INBOX_MAIL_DOMAIN` and `RELAY_INBOX_HMAC_KEY` are set; the `email()` handler drops all mail when it is off. Staging sets `in-staging.relayeverything.com`, so a preview can test the full path.

## Risks / Trade-offs

- [Email is not sealed on the way] → The card and docs say not to send health or location details. Notes are sealed once they reach the space.
- [A leaked secret address lets anyone add notes] → A forged note can only add, never read. *New address* stops it at once.
- [A copy of the directory gives every address, from `shown` and the public mail domain] → The same as a leak: notes can be added, never read, and *New address* stops it.
- [Every mail is stored, so one sender can flood a space] → Storage is cheap, and nothing is sent back, so a flood costs no money. *New address* stops it.
- [Kept mail holds data from people who have not agreed to anything yet] → It is sealed, lasts 30 days, is capped for each email, and the privacy page says so.
- [Cloudflare's 25 MB message cap] → Larger mail never arrives; the docs say so.

## UX

### Use-case brief

A signed-in person wants to send a receipt, a newsletter or a thought from their mail app without opening Relay Everything. Done means the note shows on their page. Finding the address happens once; sending happens many times a day. Edge cases: a leaked address, mail with too many files, a server with email off. The closest existing screen is the *Devices* card (`Devices.tsx`), which this card mirrors.

### Flow

Open the page → *Email* card → tap *Copy* → paste the address in a mail rule or a contact → mail arrives as a note within seconds.

### Hierarchy

The address is the card's content, with *Copy* as its one action. *New address* stays quiet as a ghost button behind a confirm, because it breaks every rule that uses the old address. The warning sits under the address as muted text.

### Review

See [review.html](review.html). The *An Email card on your page* item sketches the card.

### Components

The card uses `Card`, `Button` and `Dialog` from the app's parts, like `Devices.tsx`. Nothing new.
