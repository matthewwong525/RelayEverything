# Set up your own Relay Everything server

This guide is for the AI that sets up a person's own Relay Everything server. It makes Relay Everything in the person's own Cloudflare account: the server, the Relay Everything page, device keys and the AI connector. It installs nothing else from this repository. The person's website guide is [Run your own Relay Everything server](https://relayeverything.com/start/run-your-own/).

`app/self-host/setup.mjs` does each step the same way every time. Run it from the repository root, and read its `result=` line: `ok`, `refused` or `failed`. It never prints a key.

## What it makes

In the person's Cloudflare account, each named after the server (`relay` by default):

| Part | Name |
|---|---|
| The server and the Relay Everything page, one Worker | `relay` |
| Each person's own space for their data, one Worker | `relay-spaces` |
| The AI connector, its own Worker and sign-in store | `relay-mcp` |
| The list of accounts and device keys | `relay-db` |
| The file store for recordings | `relay-notes` |
| The webhooks' queue | `relay-webhooks` |
| The login: an Access app for the person's email | `Relay (relay)` |
| The device keys' way past the login: the server checks each key itself | `Relay Everything device keys (relay)` |

It costs nothing on Cloudflare's free plan. Tell the person this, and ask before you run `install`.

## The Relay Everything page

The page is the Relay Everything phone app, built for the web. The server opens it at its top address, the `server=` address. The person does not install Flutter: each Relay Everything release on GitHub holds the page as `relay-web-<commit>.zip`, with its SHA-256 in `relay-web-<commit>.zip.sha256`. `<commit>` is the newest commit that changed `mobile/`. Before `install` or `update` changes anything, it downloads the page for its own copy, checks the SHA-256, and puts the page in `app/public/apps/relay/`. Git ignores that folder.

When no release holds the page for the person's copy, the command stops and changes nothing. Its line names a release, such as `v1.2.0`. Run `git fetch --tags`, then `git checkout <that release>`, then run the same command again. The setup needs a copy made with `git clone`, because it reads the commit from git.

## Steps

1. **Clone the repository**, if the person has no copy: `git clone https://github.com/matthewwong525/RelayEverything`, then work in that folder. Run `npm ci` in `app/`. It needs Node 22 or newer.
2. **Get a Cloudflare key.** Send the person to https://dash.cloudflare.com/profile/api-tokens. They make a custom token for their account with these permissions:
   - Account: Workers Scripts Edit, D1 Edit, Workers R2 Storage Edit, Queues Edit, Workers KV Storage Edit
   - Account: Access: Apps and Policies Edit, Access: Service Tokens Edit, Access: Organizations, Identity Providers, and Groups Read

   Have them put it in `app/self-host/.env` as `CLOUDFLARE_API_TOKEN=<the token>`, in their own editor. Never ask for the token in the chat, and never print the file. If the token reaches more than one account, they add `CLOUDFLARE_ACCOUNT_ID=<the account's ID>` too. Git ignores the file.
3. **Check:** `node app/self-host/setup.mjs check`. Each `missing` line names the permission to add to the token, or the part to turn on once in the Cloudflare dashboard:
   - **Zero Trust:** the free plan, with a team name. It holds the login.
   - **R2:** Cloudflare can ask for a payment card before it turns R2 on, even on the free plan. Say so before the person starts.
   - **Workers:** open Workers & Pages once, to get a `workers.dev` address.
4. **Install:** `node app/self-host/setup.mjs install --email <the person's email>`. Their email is the only login. Add `--name <name>` for another name. It prints `server=` and `connector=`.
5. **Sign in:** the person opens the `server=` address, enters their email, and types the code Cloudflare sends. Their first visit makes their account and their own empty space. Only the owner's email gets an account. To let other people make one, the owner sets `RELAY_SIGN_UP` to `open` in `app/self-host/wrangler.jsonc` and runs `update`. To show people an address for questions and privacy requests on their account card, the owner sets `RELAY_CONTACT_EMAIL` to that address the same way. With no address set, the server shows no such line. `update` keeps both settings.
6. **Keys:** each Claude Code or Codex computer gets its own key when the person types `/relay:connect <the server= address>`, as step 7 shows. The phone app signs in only to the shared Relay Everything server, so on this server the person uses the Relay Everything page in a browser and the plugin. A key for their own script comes from *Settings*, *Account*, *Advanced*, *API keys*, *Add an API key*: the page shows it once. Never ask for a key in the chat.
7. **AI connector:** the person adds the `connector=` address to their AI, as [Connect your AI](https://relayeverything.com/connections/connect-your-ai/) shows. The AI app sends them to their server's own login. In Claude Code or Codex, the person uses the plugin instead: `/relay:connect <the server= address>` ([Save AI chat transcripts](https://relayeverything.com/connections/claude-code/)).

## Email notes

Email is off until the person asks for it. It needs a domain of theirs on Cloudflare, such as a subdomain of their own domain:

1. The person turns on **Email Routing** for that domain in the Cloudflare dashboard, and adds a catch-all rule with the action *Send to a Worker*, to the server's Worker: the `--name` given at install, or `relay`.
2. From `app/`, set two secrets: `npx wrangler secret put RELAY_INBOX_MAIL_DOMAIN -c ../self-host/wrangler.jsonc` with the domain, and `RELAY_INBOX_HMAC_KEY` the same way, with the output of `openssl rand -base64 32`. Secrets stay through `update`. Never print the key in the chat.
3. Point the person to [Email notes](https://relayeverything.com/app/email/): the **Email** card shows their address.

## Update my Relay Everything

When the person asks to update: `git pull`, then `npm ci` in `app/`, then `node app/self-host/setup.mjs update`. It gets [the Relay Everything page](#the-relay-everything-page) for the new copy, writes the server's settings again from this repository, applies the new database changes, then puts the new server live. If there is no page for the copy, or a database change fails, it stops, and the old server stays live. The data stays. When the connector's address changed, such as from `…/mcp` to the bare address, `update` says so: the person connects each AI app again at the new address.

A copy on a release tag has no branch to pull. To update it, run `git fetch --tags`, then `git checkout` the newest `v<x.y.z>` tag, then continue with `npm ci`.

An install made when this guide was in a top-level `self-host/` folder keeps its settings and `.env` there. Each command moves them to `app/self-host/` first, prints a `moved=` line, and removes the old folder when it is empty. The person does nothing.

An install from before spaces gets no move of its old data: the update removes the old shared tables, and the notes in them with it. Old device keys stop working too. The person makes a new key for each device on the page, as in step 6, and scans it again.

## Status

`node app/self-host/setup.mjs status` lists each part and whether the server's address answers.

## Remove my Relay Everything

`node app/self-host/setup.mjs remove` lists what it would delete. Show the person that list. It deletes every note, recording, health sample and place, and it can't be undone. Run `remove --yes` only after the person says yes in the chat.

## If something fails

- `result=refused` from `check` or `install`: fix each `missing` line, then run it again. Nothing was made.
- `no release holds the Relay Everything page`: use the release the line names, as [the Relay Everything page](#the-relay-everything-page) says. Nothing was made or changed.
- `does not match its SHA-256`: the download broke. Run the same command again. Nothing was changed.
- `result=failed`: the line before names the step. Run the same command again: each step that is done is skipped.
- `install` writes `app/self-host/wrangler.jsonc`, `app/self-host/wrangler.mcp.jsonc` and `app/self-host/wrangler.spaces.jsonc`, which `update` and `status` read. Keep them. Git ignores them.
