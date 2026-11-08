# Email notes for Relay Everything

**Status:** ready-to-ship
**Branch:** reach-people-where-they-are
**Open questions:** none

## Why

People already email all day. Today a note gets into Relay Everything only through the app, the ring, Shortcuts or the share sheet, so a receipt, a newsletter or a thought written on a laptop stays in the inbox. With email in, a person forwards or writes to one address, with nothing to install. Email is free, needs no carrier or Meta approval, and Cloudflare already handles the domain's mail, so it comes first. Text messages, WhatsApp and Telegram wait until people ask for them.

## What Changes

- **Your own notes address.** Your page gives you your own secret address. Any mail to it becomes a note, whoever sends it: the subject and words become the note text, and the attached files go with it. You can set a mail rule to forward mail on its own, such as every receipt. No mail is sent back.
  ```mermaid
  sequenceDiagram
    participant You
    participant Mail as Your secret address
    participant Space as Your space
    You->>Mail: Forward "Your receipt" with a PDF
    Mail->>Space: Note with the PDF, from Email
  ```
- **One shared address for your sign-in email.** Mail to `notes@` from the email you sign in with also becomes a note in your space. It counts only when the mail passes the sender checks, so nobody can send it in your name.
  ```mermaid
  flowchart TD
    B["notes@, from your sign-in email"] --> C["Note in your space"]
    D["notes@, fails the checks"] --> X["Dropped"]
  ```
- **Kept until you sign up.** Mail to `notes@` from an email with no account yet is kept, sealed, for 30 days. When that email signs up, the kept mail becomes notes with their first times. After 30 days, kept mail is deleted.
  ```mermaid
  sequenceDiagram
    participant New as New person
    participant Server as Relay Everything
    New->>Server: Mail to notes@ "Idea: ring charger"
    Server->>Server: Kept, sealed, 30 days
    New->>Server: Signs up with that email
    Server->>Server: Kept mail becomes notes
  ```
- **An Email card on your page.** It shows your address with *Copy*, and *New address* replaces it if it leaks. Mail to an old address then becomes no note.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Email</h3><span class="grow"/><button class="btn-ghost">Copy</button></div>
    <div class="muted">notes-k7q2m9xw@in.relayeverything.com</div>
    <div class="row gap"><span class="muted">Anything sent here becomes a note.</span><span class="grow"/><button class="btn-ghost">New address</button></div>
    <div class="muted">You can also write to notes@in.relayeverything.com from your sign-in email.</div>
    <div class="sep"/>
    <div class="muted">Email is not sealed on the way. Don't send health or location details this way.</div>
  </div>
  ```
- **Every mail is stored.** Nothing is refused for being too many. Files follow the note limits: up to 10 files of 25 MB each, and a larger or extra file is left out and named in the note.
  | Who sends | What happens |
  |---|---|
  | Anyone, to your secret address | A note in your space |
  | Your sign-in email, to `notes@` | A note in your space |
  | An email with no account, to `notes@` | Kept for 30 days, then a note if it signs up |
  | Mail to `notes@` that fails the checks | Dropped |
- **One inbox for later ways in.** Email goes through one inbox that turns a message into a note. Text messages, WhatsApp, Telegram or a browser extension can use the same inbox later. Your webhooks and your AI see each emailed note as they see a note from the app, with *Email* as where it came from.
  ```mermaid
  flowchart TD
    E["Email"] --> I["One inbox"]
    L["Later: text, chat apps"] -.-> I
    I --> N["Note in your space"]
    N --> H["Webhooks and your AI"]
  ```
- **The website explains it**, on a new *Email notes* page, with the warning about health and location.

## What the build needs

- **Email on Cloudflare**: Ready. relayeverything.com is on Cloudflare, which already sends the sign-in mail and forwards `matt@`. The build adds mail in for `in.relayeverything.com` and `in-staging.relayeverything.com`.

## Capabilities

### New Capabilities

- `relay-inbox`: one inbox that turns an emailed message into a note in its owner's space: each person's secret address, the shared `notes@` address with sender checks, mail kept for 30 days from emails with no account yet, and the page card. Later ways in reuse it.

### Modified Capabilities

- `relay-website`: a new *Email notes* page, with the warning about health and location.

## Impact

- New space migration `0007_inbox.sql`: an `inbox` device reach. New D1 migration: `relay_inbox_links` (a person's secret address, keyed by an HMAC of its local part, with a `channel` column for later ways) and `relay_inbox_held` (kept mail, sealed, with its files in the bucket under `held/`).
- A new `email()` handler and a daily `scheduled()` sweep in `worker/relay-only.ts`; the person's routes for the card under `/apps/relay/api/inbox`. A new `postal-mime` dependency.
- New secrets: the HMAC key and the mail domain. Email Routing: MX records and a catch-all rule for `in.` and `in-staging.` to the servers.
- The page gets the *Email* card. The web API, AI connector and webhook schema show a note's channel.
- Cost: Cloudflare Email Routing is free. Each message is at most 25 MB.

## Decision log

**2026-11-07** — Asked which ways to text in → chose SMS, email, Telegram and WhatsApp.
**2026-11-07** — Asked how to build the four ways → chose "One plan, turn on as ready (Recommended)": one inbox; email and Telegram first, SMS and WhatsApp when Telnyx and Meta approve.
**2026-11-07** — Asked who may send to the notes email address → chose "Only emails you approve (Recommended)": the sign-in email and added addresses, with a secret address.
**2026-11-07** — Assumed: email gets no reply, so a forged sender never makes the server send mail; mail to `notes@` must pass Cloudflare's DMARC, or SPF and DKIM, checks.
**2026-11-07** — Assumed: email is a device named *Email* in the space, so the timeline, webhooks and AI show where a note came from with no new note field.
**2026-11-07** — Assumed: a self-host and staging turn on email only when its mail domain is set; staging uses `in-staging.`.
**2026-11-07** — Assumed: the card is a sketch, not a prototype, because the staging company app has no spaces to show the card with; the build matches the sketch.
**2026-11-07** — Asked (plan note) whether to refuse unknown senders and cap notes → chose to store every note, and to keep messages from senders nobody has linked so they become notes once that person signs up; kept messages are cleared when old.
**2026-11-07** — Changed: the approved-senders list for email is removed, because every note is accepted; any mail to a person's secret address becomes a note.
**2026-11-07** — Assumed: kept mail lasts 30 days, at most 100 messages and 50 MB for each unknown email, sealed with a key made from the sender's own email, which the server does not store, so a copy of the database alone can't read it.
**2026-11-07** — Assumed: the shared `notes@` address takes mail by its `From`, and keeps mail from an email with no account until that email signs up; mail that fails DMARC there is dropped, because it can't be tied to anyone safely.
**2026-11-07** — Asked how far texting should go for now → chose "Email only (Recommended)": the plan keeps only the notes email; SMS, WhatsApp and Telegram wait until people ask for them, because each needs approvals, compliance pages or per-message costs that are too early now. The change is renamed from `texting-inbox` to `email-notes`.
**2026-11-07** — Asked what to do with the Telnyx number → chose "Keep it, $1 a month (Recommended)": +1 833 865 4321 stays on the Telnyx account for when SMS comes back; its toll-free check is paused.
**2026-11-07** — Changed: link codes, replies, the daily reply limit and voice to words leave the plan, because email needs no link step and sends nothing back, and an emailed voice memo is kept as a file.
**2026-11-08** — Assumed: the mail domain, `RELAY_INBOX_MAIL_DOMAIN`, is a public wrangler var on the shared servers and only `RELAY_INBOX_HMAC_KEY` is secret, because a domain copied into `.env` makes the public-repo check refuse every page that names it; a self-host sets both as secrets, which an update keeps.
**2026-11-08** — Assumed: mail to `notes@` that fails the sender checks is dropped with no answer; mail to an unknown or old address, to a server with email off, or that can't be read is refused at Email Routing, which tells the sender's mail service, not the person.
**2026-11-08** — Assumed: the sender check reads only the topmost `Authentication-Results` or `ARC-Authentication-Results` header, and only when its authserv-id is `mx.cloudflare.net`; the live send in 4.3 must confirm the header Cloudflare adds.
**2026-11-08** — Assumed: the reply-quote cut removes only a trailing `>` block and its *On … wrote:* line, so a forwarded mail stays whole.
**2026-11-08** — Assumed: a self-host has no Cron Trigger, because its install may hold no WongStack-shaped cron; each new kept mail runs the sweep there instead. The shared server keeps the daily cron, and `POST inbox/sweep` runs it by hand on staging only.
**2026-11-08** — Assumed: a self-host's Access sign-in makes its person without claiming kept mail, because `notes@` mail on a self-host comes mostly from its owner, who already has an account.
**2026-11-08** — Assumed: no seed rows, because a notes address row needs the server's secret HMAC key to be found; the checker's address is made on its first `GET inbox`.
**2026-11-08** — Check: `containsCredential` in `app/worker/api/contract.ts` now lets an answer name `RELAY_INBOX_MAIL_DOMAIN`, as it lets the other committed settings, because every notes address the Email card shows ends with that public domain; every other text binding is still refused. A WongStack update must keep this name in `COMMITTED`.
**2026-11-08** — Assumed: the space-schema test's stand-in storage now runs each migration in a real transaction, as a Durable Object does, so a step that rebuilds a parent table, such as `0007`, is tested as it runs live; this makes the test stricter, not looser.
**2026-11-08** — Assumed: a sign-in claims any kept mail still waiting for that email, not only the first sign-up, because a claim that stops partway would otherwise lose the rest to the 30-day sweep.
**2026-11-08** — Assumed: a picture pasted into a mail's body becomes a note file when it is 20 KB or more, and smaller inline pictures such as logos are left out unnamed, because the server can't tell a pasted photo from a logo by its place, and naming every logo would clutter the note.
**2026-11-08** — Asked how to turn on mail for `in.` and `in-staging.`, since the repository's Cloudflare token can't change Email Routing → chose "I'll click it on (Recommended)": the person adds both subdomains in the Cloudflare dashboard, and the build adds the rules and tests them.
**2026-11-08** — Assumed: live's `in.` mail goes through the zone's one catch-all rule to the live server, and staging uses one literal rule for each test address, because a zone has only one catch-all and Email Routing rules match single addresses.
**2026-11-08** — Checkpoint: the build, its review fixes and staging's mail setup are saved; the staging mail tests (4.3), the website preview (4.4) and turning on live mail after the publish (4.5) remain.
**2026-11-08** — Checked on staging: a forwarded invoice to the card's address became a note with its PDF; mail to `notes@in-staging.` from the sign-in Gmail passed the sender check, so Cloudflare's `Authentication-Results` header is the one the check reads; after *New address*, mail to the old address bounced and made no note.
**2026-11-08** — Assumed: turning on live mail moves from task 4.5 to an after-publish note in `tasks.md`, because a task can't wait for its own publish; the ship report carries it as the next step.
**2026-11-08** — Archive checkpoint: built, reviewed, checked on staging and archived for publish; live mail turns on after the publish, by the note in `tasks.md`.
**2026-11-08** — Assumed: the space step is `0008_inbox.sql`, not `0007_inbox.sql`, because main added `0007_note_files.sql` first; and the inbox wakes webhooks after it seals a note's files, as main's file upload now does, so an emailed file reaches webhooks as `note.file`.
