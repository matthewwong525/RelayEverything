# Use your Gmail, Calendar, Drive and Contacts through Relay Everything

**Status:** parked
**Branch:** ios-data-ideas
**Open questions:** none

## Why

Your email, calendar, files and contacts say much about your day, but today Relay Everything can't reach them. Google already keeps them, so Relay Everything doesn't copy them: it passes each question to Google and passes the answer back. It stores only your Google sign-in. Your scripts and AI apps then get them in the same place as your notes, health and places.

## What Changes

- **Connect Google on your page.** A new *Google* card on your Relay Everything page has one button, *Connect Google*. Google asks you to allow Gmail, Calendar, Drive and Contacts, and the card then shows your Google address. Until Google finishes its review, Google first shows a warning page, *Google hasn't verified this app*. You click *Advanced*, then *Go to Relay Everything*.
  ```screen
  <div class="card col gap phone">
    <h3>Google</h3>
    <span>Let your scripts and AI apps read and use your Gmail, Calendar, Drive and Contacts. Relay Everything keeps no copy: it asks Google each time.</span>
    <div class="row gap"><span class="grow"></span><button class="btn-primary">Connect Google</button></div>
  </div>
  ```
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Google</h3><span class="tag">Connected</span></div>
    <span>you@gmail.com</span>
    <span class="muted">Gmail, Calendar, Drive, Contacts · connected 7 Nov</span>
    <div class="row gap"><span class="grow"></span><button class="btn-ghost">Disconnect</button></div>
  </div>
  ```
  These sketches stand in for pictures: the preview can't open a person's space, so the page can't run there.
- **Nothing from Google is stored.** Each question goes to Google at that moment, and the answer goes straight back to the app that asked. Relay Everything keeps only your Google sign-in, locked with your space's own key, as recordings are. No email, event, file or contact goes in your space, in a log, or to your webhooks.
  ```mermaid
  sequenceDiagram
    participant A as Your script or AI
    participant R as Relay Everything
    participant G as Google
    A->>R: Search my email for "invoice"
    R->>G: The same question, with your sign-in
    G-->>R: The emails
    R-->>A: The emails, not kept
  ```
- **Your scripts get all of Gmail, Calendar and Drive, and your contacts, through the API.** The Relay Everything web API gets four new paths: `google/gmail/`, `google/calendar/`, `google/drive/` and `google/contacts/`. Each passes your request to Google's own API, so Google's own documents tell you what each path does. You can read, search, send, draft, label, archive and put mail in the bin. You can read, add, change and delete events. You can search, read, upload, change and put files in the bin. You can read your contacts and the people you email.
  | Ask | Goes to |
  | --- | --- |
  | `GET /v1/google/gmail/messages?q=invoice` | Gmail: search messages |
  | `POST /v1/google/gmail/messages/send` | Gmail: send an email |
  | `GET /v1/google/calendar/calendars/primary/events` | Calendar: list events |
  | `POST /v1/google/calendar/calendars/primary/events` | Calendar: add an event |
  | `GET /v1/google/drive/files?q=name contains 'lease'` | Drive: search files |
  | `GET /v1/google/contacts/people:searchContacts?query=Sam` | Contacts: find a person |
- **AI apps get Gmail, Calendar, Drive and Contacts tools.** The AI connector gets new tools, so you can ask Claude *what's on my calendar tomorrow?* or *reply to Sam's email and say yes*, or *find my lease in Drive*. A tool that sends, changes or deletes is marked so, and your AI app asks you before it runs one.
  | Tool | What it does |
  | --- | --- |
  | Search email | Emails that match a Gmail search, newest first |
  | Read email | One email or thread, with its words |
  | Send email | Sends an email or a reply from your address |
  | Draft email | Puts a draft in your Gmail |
  | Change email | Archives, labels, marks read, or puts it in the bin |
  | List events | Events from one time to another |
  | Add event | A new event on your calendar |
  | Change event | Moves or edits an event |
  | Delete event | Takes an event off your calendar |
  | Search files | Drive files that match a name or words inside |
  | Read file | A file's words: a Doc, a Sheet or a text file |
  | Save file | A new Doc or file in your Drive |
  | Change file | Renames, moves, or puts it in the bin |
  | Find contact | A person's name, email and phone, from your contacts and the people you email |
- **A sent email can't be undone.** An app or AI that you connected can send email from your address. Before you connect an app, the *Connect X?* page says so.
  ```screen
  <div class="card col gap phone">
    <h3>Connect Claude to Relay Everything?</h3>
    <span>It can then read your notes, health, places and saved chats, and add notes. If you connected Google, it can also read and send your email, change your calendar and your Drive files, and read your contacts.</span>
    <span class="muted">Its answers go to claude.ai.</span>
    <div class="row gap"><button class="btn-primary">Connect</button><button class="btn-ghost">Cancel</button></div>
  </div>
  ```
- **Disconnect stops it at once.** *Disconnect* on the Google card ends the sign-in at Google and deletes it from your space. Deleting your account does the same. An app connected before this change reaches Google only after you connect it again.
  ```mermaid
  flowchart TD
    A["Disconnect"] --> B["Google ends the sign-in"]
    B --> C["Your space deletes it"]
    C --> D["Next Google question: Connect Google first"]
  ```
- **We ask Google for its review.** To let more than 100 people connect, and to remove the warning page, Google must check the app. Gmail and Drive need a security check by a company that Google names, paid each year. The build sends the request with a privacy page, a short video and the domain check. Google decides, and that can take some weeks.
  ```mermaid
  flowchart TD
    A["Privacy page and video"] --> B["Ask Google for review"]
    B --> C["Security check, paid"]
    C --> D["Google approves"]
    D --> E["No warning, no 100 limit"]
  ```
- **The website tells how.** A new *Google* page says how to connect, what each tool and path does, and what Relay Everything keeps. The privacy page says how Google data is used, in the words Google asks for.

Non-goals: storing or searching your mail or events inside Relay Everything; sending Google data to your webhooks; Google Photos, Tasks or Keep; editing inside a Doc or a Sheet; another mail or calendar service, such as Outlook; picking a Google service per app; deleting an email or a file for ever (the bin keeps it 30 days); changing your contacts.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are in `.env`.
- **Google sign-in client**: Ready, the server already signs in with Google (`RELAY_GOOGLE_CLIENT_ID`); this change uses the same Google Cloud project. Its secret is only on the server, so the build makes a second secret for the AI connector.
- **Your Google Cloud sign-in**: Needs you. The shared browser is signed in to Google as ithinkwong@gmail.com, which Google Cloud blocks. During the build, a live view opens once: you sign in as matthewwong525@gmail.com, and the build adds the Gmail, Calendar, Drive and Contacts permissions, two return addresses and the second secret.
  ```form
  text: OK to sign in once through a live view during the build? (yes or no)
  ```

The build starts only after the plan *Let your own scripts and other apps read and add to Relay Everything* is live, because this change adds to its API and its sign-in. Google's review comes after the build: you put the short video on YouTube, and you pick and pay the security check company. The build sends nothing that costs money without your OK.

## Capabilities

### New Capabilities

- `relay-google`: a person connects their Google account; the API and the AI connector pass requests to Gmail, Calendar, Drive and Contacts with it; only the sealed sign-in is stored; disconnect and account delete end it.

### Modified Capabilities

None. The AI connector's rule that no tool changes Relay Everything data stays true: Google tools act on Google, not on the space.

## Impact

- Builds on the unshipped change `relay-api-and-connector-add` (the `/v1` API, API keys, grant `adds`); this change ships after it.
- `app/worker/apps/relay/google/`: new `connect.ts` (start, callback, disconnect), `token.ts` (sealed refresh token, access token refresh, revoke), `proxy.ts` (path allow-list, pass-through, no logging of bodies).
- `app/worker/apps/relay/space.ts`: seal and open a small secret with the space's file key; `account.ts`: delete revokes at Google.
- `schema/space-migrations/`: a new numbered file adds `relay_google` (one row: Google email, scopes, sealed refresh token, connected time). Other open plans also add `0003_*`: whichever ships second takes the next number.
- `app/worker/relay-mcp/`: new `google-tools.ts` (fourteen tools), `tools.ts` registers them, `auth.ts` consent words, `api.ts` routes `/v1/google/*`.
- `app/src/apps/relay/`: new `GoogleCard.tsx`, placed in `App.tsx`.
- `app/wrangler.relay-mcp.jsonc`: `RELAY_GOOGLE_CLIENT_ID`; `scripts/relay-mcp-setup.mjs` sets `RELAY_GOOGLE_SIGN_IN_SECRET` on the connector from `.env`; `.env.example` names it.
- Docs: `site/src/content/docs/connections/google.md` (new, listed in `scripts/product-name.test.mjs`), `site/src/content/docs/privacy.md` (Google's Limited Use words), `connections/connect-your-ai.md`, `api/reference.md` (`npm run relay:api-doc`); `wiki/stack/relay-google.md` (new) linked from `wiki/stack/README.md`.
- Outside the repo: Google Cloud console (scopes, return addresses, publish status, verification request), Search Console domain check, YouTube video, the security check.

## Decision log

**2026-11-07** — Asked where Google and the Share button go → chose "Google here, Share in a new one (Recommended)".
**2026-11-07** — Asked how people get Gmail access, given Google's review rules → chose "Both, and start the paid review".
**2026-11-07** — Asked what an app or AI may do with Google data → chose read and add for emails and calendar events, through the app; then, asked what "add" means for email → answered: Relay Everything exposes an API that lets the person work with Gmail, so it has the full range of capability.
**2026-11-07** — Asked which ways in Google data has → chose "The API and AI connector (Recommended)": the page has only Connect Google and Disconnect.
**2026-11-07** — The person said: don't store email and calendar data; store only what can't be relayed.
**2026-11-07** — Assumed: Gmail's `gmail.modify` permission, not full `mail.google.com`, because it does everything but delete for ever, and the bin keeps a mistake for 30 days.
**2026-11-07** — Assumed: Calendar gets full event access (read, add, change, delete), because the person asked for the full range on Gmail and the same reach on Calendar is one permission.
**2026-11-07** — Assumed: the API passes requests through to Google's own paths under an allow-list, and the AI gets fourteen fixed tools, because a pass-through gives the full range with Google's own documents, and an AI works best with few clear tools.
**2026-11-07** — Assumed: every connected app and API key made after this change reaches Google when Google is connected, as the API plan's "all or nothing" choice says; an older grant connects again first; phone and chat keys never reach Google.
**2026-11-07** — Assumed: the app goes to "In production" without the review while the review runs, because a "Testing" app's Google sign-in ends after 7 days; until the review, people see Google's warning page and at most 100 can connect.
**2026-11-07** — Assumed: the same Google Cloud project and client as sign-in, because Google reviews one project, and the sign-in keeps asking only for email.
**2026-11-07** — Assumed: Shortcuts stays out, because another workspace builds it.
**2026-11-07** — Asked which Google services to add beside Gmail and Calendar → chose Drive and Contacts; not Tasks, nor editing inside Docs and Sheets.
**2026-11-07** — Assumed: Drive gets the full `drive` permission (search, read, upload, change, bin) but no delete for ever, because the person asked for the full range and the bin keeps a mistake; it is restricted like Gmail, so one security check covers both.
**2026-11-07** — Assumed: Contacts is read-only (`contacts.readonly` and `contacts.other.readonly`), because the choice was to find names and addresses, and "other contacts" holds the people you email but never saved.
**2026-11-07** — Assumed: `/v1/google/` lives in the shipped connector API, `relay-mcp/api.ts`, and the one door to Google in `apps/relay/google/proxy.ts`, which throws `GoogleRefusal` for `api.ts` and the tools to answer, because an app folder can't import `relay-mcp/`; the problem codes gain `503 temporarily_unavailable`.
**2026-11-07** — Assumed: a grant carries `google: true` beside the shipped `adds`, and the connector's `Asker` a `google` flag; an API key's asker always has it.
**2026-11-07** — Assumed: connect and callback answer at `/apps/relay/google/{connect,callback}`, wired only in `relay-only.ts`, the shared server; the card's status and disconnect are the API routes `GET google` and `POST google-disconnect`. Connect takes a session or an Access caller, as the AI connector's sign-in does.
**2026-11-07** — Assumed: the access-token cache is keyed by person and checked against the sealed bytes, and each call reads the row, so a disconnect or a new connection stops the old token at once.
**2026-11-07** — Assumed: the connector's CORS widens to the five methods and the upload headers, and exposes `Location`, `Range` and `ETag`; a resumable upload's `Location` is rewritten to the caller's own `/v1/google/drive/upload/`.
**2026-11-07** — Assumed: Drive's empty-the-bin, `DELETE files/trash`, is refused by the same `files/<id>` rule as a delete for ever.
**2026-11-07** — Assumed: Read file refuses a PDF, because reading one through a Doc copy changed the person's Drive while the tool was marked read-only; refusing keeps the tool read-only and can be widened later.
**2026-11-07** — Assumed: the API refuses deleting a Gmail draft, because Gmail deletes a draft for good, and the plan refuses every delete for ever.
**2026-11-07** — Assumed: the OpenAPI file gives the four services as one path, `/v1/google/{service}/{path}`, with five methods, and its error list comes from the API's own codes.
**2026-11-07** — Assumed: the setup script puts the Google secret from `.env` on each run, because Cloudflare never shows a secret back; with none in `.env`, it skips Google and says so by name.
**2026-11-07** — Assumed: no rows in `schema/seed.sql`, because `relay_google` is in a person's space, not the directory database, and a sealed token can only be made by a space.
**2026-11-07** — Assumed: the new site page needs no list edit in `scripts/product-name.test.mjs`, because that list already holds all of `site/src/content`.
**2026-11-07** — Assumed: a tool says "Google gave no reason." when Google's refusal has no words, because the proxy passes on the status but no status text.
- Check: `tools.test.ts` "holds no statement but SELECT" allows one exact string in `google-tools.ts`, `{ method: "DELETE", query: { sendUpdates: "all" } }`, because the word is the HTTP method `delete_event` sends to Google, not SQL.
- Check: `space-schema.test.ts` finds the `0003` migration by name, not as the last one, so its widening test still runs with `0004` after it.
**2026-11-07** — Parked before task 6.1: the person chose to focus on notes first ("this is later"). The build, its tests and the second review's fixes are saved; the Google Cloud console step (sign-in as matthewwong525@gmail.com needs a passkey or a password through a live view), the staging trial and Google's review wait. The space migration is now `0005_google.sql`, because `0004_attachments.sql` shipped first.
