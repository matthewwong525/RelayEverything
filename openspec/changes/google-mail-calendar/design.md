# Design

## Context

See proposal.md for why. Today the shared server (`relay-everything-server`) signs people in with Google through `app/worker/apps/relay/sign-in/oidc.ts`, asking only `openid email`, with the client `RELAY_GOOGLE_CLIENT_ID` and the secret `RELAY_GOOGLE_SIGN_IN_SECRET` (a Worker secret, not in `.env`). Each person's data is a Durable Object space, opened only through `space.ts` ([person spaces](../../../wiki/relay-spaces.md)); recordings are sealed with the space's file key.

The change `relay-api-and-connector-add` (workspace *APPLY: Let your own scripts and other apps read and add to Relay Everything*) puts a `/v1` web API on the connector Worker, reached with a connected app's OAuth token or an `api` key, and gives grants an `adds` prop. This change ships after it and adds to both.

## Goals / Non-Goals

**Goals:**
- One Google connection per space, held as a sealed refresh token.
- A pass-through for Gmail, Calendar, Drive and Contacts: full reach for the API, fourteen tools for the AI.
- No Google data at rest anywhere, and no Google bodies in logs.

**Non-Goals:**
- Caching Google answers, even for a short time.
- Push from Google (Gmail watch, Calendar channels): it needs stored state and a public webhook.
- A Google connection shared by several people.

## Decisions

**Connect is its own OAuth flow, separate from sign-in.** `GET /apps/relay/google/connect` (session only) sends the browser to Google with `scope=openid email https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/drive https://www.googleapis.com/auth/contacts.readonly https://www.googleapis.com/auth/contacts.other.readonly`, `access_type=offline`, `prompt=consent`, PKCE and `state` in a short cookie, as `oidc.ts` does. `GET /apps/relay/google/callback` trades the code, checks the ID token, checks that every scope was granted (Google lets a person untick one), and stores the refresh token. Alternative: add the scopes to sign-in. Rejected: every sign-in would then ask for Gmail, and a person who only signs in would hit the unverified-app page.

**Same Google Cloud project and client.** Google reviews a project; one project gets one review. The client gets two more return addresses (live and staging `…/apps/relay/google/callback`).

**The refresh token is sealed with the space's file key.** A new space migration adds `relay_google (id INTEGER PRIMARY KEY CHECK (id = 1), email TEXT, scopes TEXT, token BLOB, connected_at INTEGER)`. `space.ts` gets `seal(name, bytes)` and `open(name, bytes)` beside `filesOf`, AES-256-GCM with the store name `google` as associated data, so the one-door rule holds. Alternative: a Worker-wide key. Rejected: deleting a space must make its token useless with no other step.

**Access tokens live only in memory.** `google/token.ts` refreshes against `https://oauth2.googleapis.com/token` and keeps the access token in a per-isolate map keyed by person id until one minute before it ends. A refresh that answers `invalid_grant` (the person revoked at Google) deletes the row, so the page shows *Connect Google* again.

**The connector Worker gets the Google client too.** The `/v1` API and the tools run on the connector, which must refresh tokens. Google shows a client secret only when it is made, so the build adds a second secret to the same client, saves it in `.env` as `RELAY_GOOGLE_SIGN_IN_SECRET`, and sets it on both the server and the connector (`relay-mcp-setup.mjs` sets it from `.env`). Alternative: the connector asks the server over a service binding. Rejected: the server binds the connector, not the other way, and a loop of bindings breaks the deploy order.

**The API is a pass-through under an allow-list.** `/v1/google/gmail/<rest>` maps to `https://gmail.googleapis.com/gmail/v1/users/me/<rest>`; `/v1/google/calendar/<rest>` maps to `https://www.googleapis.com/calendar/v3/<rest>`; `/v1/google/drive/upload/<rest>` maps to `https://www.googleapis.com/upload/drive/v3/<rest>` and `/v1/google/drive/<rest>` to `https://www.googleapis.com/drive/v3/<rest>`; `/v1/google/contacts/<rest>` maps to `https://people.googleapis.com/v1/<rest>`, `GET` only. `proxy.ts` allows `GET POST PUT PATCH DELETE`, keeps the query, forwards `content-type` and the body (up to 100 MB, Workers' request limit; Drive files above it use Google's resumable upload, which the same path passes), and returns Google's status, `content-type` and body as a stream. It refuses: a `rest` with `..`, `//` or an encoded slash; Gmail paths for another user (`users/<other>`); and Gmail's permanent delete paths (`messages/<id>` with `DELETE`, `messages/batchDelete`, `threads/<id>` with `DELETE`, and `drafts/<id>` with `DELETE`, which deletes a draft for good), which `gmail.modify` refuses anyway; Drive's `DELETE files/<id>` and `files/emptyTrash`, which `drive` would allow. Calendar answers keep Google's own error. Alternative: curated REST routes. Rejected: the person asked for the full range, and Google's own documents then describe every path.

**Fourteen fixed AI tools.** `relay-mcp/google-tools.ts` adds `search_email`, `read_email`, `send_email`, `draft_email`, `change_email`, `list_events`, `add_event`, `change_event`, `delete_event`, `search_files`, `read_file`, `save_file`, `change_file`, `find_contact`. Read tools have `readOnlyHint: true`; the rest `readOnlyHint: false`, and `send_email` and `delete_event` also `destructiveHint: true`, so clients such as Claude ask the person first. `read_email` gives plain text (HTML turned to text, capped at 20,000 characters), never attachments. `read_file` exports a Doc as text, a Sheet as CSV, and reads a text file's words, capped at 20,000 characters; it refuses PDFs, images and other binary files with the file's name and Drive link, and changes nothing in Drive. `save_file` makes a Doc or a text file from words. `find_contact` searches contacts and other contacts together. `search_email` and `search_files` cap at 25 and pages with Google's `pageToken`. Each tool builds its request and calls the same `proxy.ts`, so one door reaches Google. Alternative: one generic `google_request` tool. Rejected: an AI picks and fills fixed tools far better.

**Who reaches Google.** The caller kinds that reach `/v1` (an `api` key, a grant with `adds`, and the page's session for status) reach Google; `phone` and `chats` keys never do. A grant gets a new prop `google: true` at consent, so a grant from before this change is refused with *connect again*. The consent words in `relay-mcp/auth.ts` name Gmail, Calendar, Drive and Contacts.

**Nothing is logged.** `proxy.ts` logs only method, the first path segment after `gmail`/`calendar`, status and time. A test reads the module and fails on a `console` call that names a body or query.

**Disconnect and delete.** `POST /apps/relay/google-disconnect` posts the refresh token to `https://oauth2.googleapis.com/revoke`, then deletes the row and the cached access token. `account.ts` does the same before it deletes the space; a revoke that fails is not retried, since the space key goes with the space.

**The `relay-ai-connector` spec stays as it is.** Its rule speaks of Relay Everything data; Google tools change Google, not the space. So this change adds only `relay-google`, and does not edit the same requirement that `relay-api-and-connector-add` edits.

## UX

### Use-case brief
A signed-in person on their Relay Everything page, usually at a computer, wants their AI and scripts to reach their mail, calendar, files and contacts. Done is the card showing *Connected* and their Google address. They do this once; *Disconnect* is rare.

### Flow
*Connect Google* → Google's account picker → (until review) the unverified warning → allow the four services → back to the page, card shows *Connected*. Cancel at Google → back to the page, card unchanged, no error. A person who unticks a permission → back to the page, card says *Allow Gmail, Calendar, Drive and Contacts to connect* with *Connect Google* again.

### Layout
One card below the AI apps card, same shape: a title, one line on what it does and that nothing is kept, one primary button. Connected: a *Connected* tag, the address, a muted line with what is allowed and when, and a ghost *Disconnect* with the same confirm dialog as AI apps.

### States
Not connected; connected; came back with a missing permission; disconnect confirm; Google turned off on this server (no client values): the card is hidden.

## Risks / Trade-offs

- [Google may refuse the review, or ask for changes, because Gmail data goes on to AI apps] → The privacy page states Google's Limited Use rules: data goes only to the app the person connected and asked, is never stored, never used for ads or to train a model. Until approval, the app works for up to 100 people with the warning page.
- [The security check costs money each year] → The person picks the assessor and pays; the build sends no request that costs money without an OK.
- [An AI sends a wrong email] → `destructiveHint` makes clients ask first; the consent page says sent email can't be undone.
- [A large Gmail or Drive answer streams through a Worker] → Answers stream without buffering; an upload above 100 MB uses Google's resumable upload in parts.
- [Drive reach is wide: every file the person has] → The same as Gmail's reach; the consent page names Drive, and no tool deletes for ever.
- [A stolen API key now reaches email] → It already reached notes and health; *Turn off* stops it at once, and Google's own security page lists Relay Everything for a full cut-off.
- [Space migration numbers collide with other open plans] → Whichever ships second renames its file to the next number before it ships.

## Migration Plan

1. After `relay-api-and-connector-add` is live: in Google Cloud console, add the five scopes to the consent screen, the two return addresses, a second client secret; set the app to *In production*.
2. Deploy order as [person spaces](../../../wiki/relay-spaces.md#the-workers-and-their-order): spaces Worker (new migration), connector (new secret, tools, API), server.
3. Try it on staging with the owner's Google account; then live.
4. Send the verification request: privacy page, home page, domain check in Search Console, the video, scope reasons.

Rollback: hide the card and refuse `/v1/google/*`; revoke stored tokens with a one-off run over spaces that have a row. Removing the scopes from the consent screen stops new grants.
