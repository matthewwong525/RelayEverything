# Relay Everything's Google connection

Relay Everything's Google connection lets a person's AI apps and API keys reach their own Gmail, Google Calendar, Google Drive and Google Contacts through [the AI connector](relay-ai-connector.md). Relay Everything passes each request on and keeps none of the data. It is part of [the Cloudflare stack](README.md). The website owns how a person uses it: [Connect Google](../../site/src/content/docs/connections/google.md).

## How it works

1. **Connect.** The page's **Google** card links to `GET /apps/relay/google/connect` on the server. Only a person signed in on the page (a session or Access caller) may start: a device key, the checker or a service token is refused. The server sends the browser to Google for `openid email` and five scopes (`gmail.modify`, `calendar`, `drive`, `contacts.readonly`, `contacts.other.readonly`), offline, with `prompt=consent`, PKCE, `state` and a nonce in the `relay_google` cookie. Google's sign-in for the page asks only `openid email`: connecting is its own flow, so a person who only signs in never sees the Gmail warning.
2. **Callback.** `/apps/relay/google/callback` checks `state` and that the same person finishes, trades the code, and checks the ID token. A sign-in that leaves out a scope is ended at Google and not kept. A good one goes in the space's `relay_google` table: one row with the Google address, the scopes, and the refresh token sealed with the space's file key under the name `google` ([person spaces](../relay-spaces.md#recordings)). Deleting the space makes the token useless with no other step.
3. **Use.** The connector's 14 Google tools and its `/v1/google/<service>/…` routes go through one door, [`proxy.ts`](../../app/worker/apps/relay/google/proxy.ts). An access token lasts an hour in the isolate's memory only. A refresh that Google answers `invalid_grant` deletes the row, so the card offers **Connect Google** again.
4. **Disconnect.** `POST google-disconnect`, and account deletion, end the sign-in at Google's revoke address and delete the row.

Who reaches it: an API key (`reaches = 'api'`) and an AI app whose grant carries `google: true`. A grant gets it at consent, after the consent page names Google. An app connected before that is told to connect again; a phone or chat key never reaches the connector's API.

## What the door refuses

[`proxy.ts`](../../app/worker/apps/relay/google/proxy.ts) passes only the four services' bases, and refuses before Google sees the request:

- **A delete for ever.** Gmail `DELETE messages/<id>`, `threads/<id>` and `drafts/<id>` (a deleted draft skips the bin), `POST messages/batchDelete`, and Drive `DELETE files/<id>`, which also covers `files/trash`. The bin keeps a mistake 30 days. A Calendar event delete is allowed: it is the one way to cancel an event.
- **Another mailbox.** Gmail paths start after `users/me/`.
- **An odd path.** An empty, `.` or `..` segment, or an escaped slash or backslash.
- **A change to Contacts.** The scopes only read, and the door takes only GET.

It sends Google only the sign-in and the upload headers, and gives back Google's status, type and body as they stream. Its log line names the service, the first path part, the method, the status and the time: never a body, a query or a token. A test fails on any other `console` call there.

The `read_file` tool reads only Google files and text files, and refuses a PDF with its Drive link: Drive gives words only from its own files, and a PDF's words need a Doc copy, which changes the person's Drive. A refresh that fails for another reason than `invalid_grant` answers `503`, and the row stays.

## Set it up

The server and the connector share the sign-in client of the Google Cloud project `relay-everything`. The client ID is not secret and sits in [`app/wrangler.relay.jsonc`](../../app/wrangler.relay.jsonc) and [`app/wrangler.relay-mcp.jsonc`](../../app/wrangler.relay-mcp.jsonc). The client secret, `RELAY_GOOGLE_SIGN_IN_SECRET`, is a Worker secret on both:

- **The connector.** Save it in `.env`, then run `node scripts/relay-mcp-setup.mjs --staging` and the live run: setup puts it on the connector each run. `--check` says whether `.env` holds it, by name only.
- **The server.** It reads the same secret from `app/.dev.vars`, as it does for sign-in.

In the Google Cloud console, under **Google Auth Platform**:

1. **Data access**: add the five scopes.
2. **Clients → Relay Everything web**: add `https://app.relayeverything.com/apps/relay/google/callback` and `https://app-staging.relayeverything.com/apps/relay/google/callback`. Google shows a client secret only when it is made, so add a second secret for `.env` and keep the first for sign-in until both Workers hold the new one.
3. **Audience**: set the app to *In production*. Until Google's review, up to 100 people can connect, past a *Google hasn't verified this app* page.

Deploy the spaces Worker first: its `0005_google.sql` migration adds `relay_google` ([the Workers and their order](../relay-spaces.md#the-workers-and-their-order)).

## Google's review

Gmail and Drive are restricted scopes, so Google checks the app before it lifts the 100-person limit:

1. Verify `relayeverything.com` in Google Search Console.
2. The privacy page states Google's Limited Use words: [Privacy](../../site/src/content/docs/privacy.md#google).
3. Send the verification request with a video of the connect flow and a reason for each scope.
4. A security check by a company Google names, each year, paid by the owner.

## Where the code is

- [`app/worker/apps/relay/google/`](../../app/worker/apps/relay/google/connect.ts): connect, the sealed token, and the door.
- [`app/worker/relay-mcp/google-tools.ts`](../../app/worker/relay-mcp/google-tools.ts): the 14 tools; [`google-mail.ts`](../../app/worker/relay-mcp/google-mail.ts) reads and writes emails.
- [`app/worker/relay-mcp/api.ts`](../../app/worker/relay-mcp/api.ts): `/v1/google/`.
- [`app/src/apps/relay/GoogleCard.tsx`](../../app/src/apps/relay/GoogleCard.tsx): the page's card.
