# Set up your own Relay Everything server

This guide is for the AI that sets up a person's own Relay Everything server. It makes Relay Everything in the person's own Cloudflare account: the server, the Relay Everything page, device keys and the AI connector. It installs nothing else from this repository. The person's website guide is [Run your own Relay Everything server](https://relayeverything.com/start/run-your-own/).

`self-host/setup.mjs` does each step the same way every time. Run it from the repository root, and read its `result=` line: `ok`, `refused` or `failed`. It never prints a key.

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

## Steps

1. **Clone the repository**, if the person has no copy: `git clone https://github.com/matthewwong525/RelayEverything`, then work in that folder. Run `npm ci` in `app/`. It needs Node 22 or newer.
2. **Get a Cloudflare key.** Send the person to https://dash.cloudflare.com/profile/api-tokens. They make a custom token for their account with these permissions:
   - Account: Workers Scripts Edit, D1 Edit, Workers R2 Storage Edit, Queues Edit, Workers KV Storage Edit
   - Account: Access: Apps and Policies Edit, Access: Service Tokens Edit, Access: Organizations, Identity Providers, and Groups Read

   Have them put it in `self-host/.env` as `CLOUDFLARE_API_TOKEN=<the token>`, in their own editor. Never ask for the token in the chat, and never print the file. If the token reaches more than one account, they add `CLOUDFLARE_ACCOUNT_ID=<the account's ID>` too. Git ignores the file.
3. **Check:** `node self-host/setup.mjs check`. Each `missing` line names the permission to add to the token, or the part to turn on once in the Cloudflare dashboard:
   - **Zero Trust:** the free plan, with a team name. It holds the login.
   - **R2:** Cloudflare can ask for a payment card before it turns R2 on, even on the free plan. Say so before the person starts.
   - **Workers:** open Workers & Pages once, to get a `workers.dev` address.
4. **Install:** `node self-host/setup.mjs install --email <the person's email>`. Their email is the only login. Add `--name <name>` for another name. It prints `server=` and `connector=`.
5. **Sign in:** the person opens the `server=` address, enters their email, and types the code Cloudflare sends. Their first visit makes their account and their own empty space. Only the owner's email gets an account. To let other people make one, the owner sets `RELAY_SIGN_UP` to `open` in `self-host/wrangler.jsonc` and runs `update`. To show people an address for questions and privacy requests on their account card, the owner sets `RELAY_CONTACT_EMAIL` to that address the same way. With no address set, the server shows no such line. `update` keeps both settings.
6. **Keys:** on the Relay Everything page, the person taps *Add a device* for each phone and each Claude Code computer. The page shows the key once, as a QR code. Never ask for a key in the chat. Then point them to [Connect a phone](https://relayeverything.com/start/connect-a-phone/).
7. **AI connector:** the person adds the `connector=` address to their AI, as [Connect your AI](https://relayeverything.com/connections/connect-your-ai/) shows. The AI app sends them to their server's own login.

## Email notes

Email is off until the person asks for it. It needs a domain of theirs on Cloudflare, such as a subdomain of their own domain:

1. The person turns on **Email Routing** for that domain in the Cloudflare dashboard, and adds a catch-all rule with the action *Send to a Worker*, to the server's Worker: the `--name` given at install, or `relay`.
2. From `app/`, set two secrets: `npx wrangler secret put RELAY_INBOX_MAIL_DOMAIN -c ../self-host/wrangler.jsonc` with the domain, and `RELAY_INBOX_HMAC_KEY` the same way, with the output of `openssl rand -base64 32`. Secrets stay through `update`. Never print the key in the chat.
3. Point the person to [Email notes](https://relayeverything.com/app/email/): the **Email** card shows their address.

## Update my Relay Everything

When the person asks to update: `git pull`, then `npm ci` in `app/`, then `node self-host/setup.mjs update`. It writes the server's settings again from this repository, applies the new database changes, then puts the new server live. If a database change fails, it stops, and the old server stays live. The data stays.

An install from before spaces gets no move of its old data: the update removes the old shared tables, and the notes in them with it. Old device keys stop working too. The person makes a new key for each device on the page, as in step 6, and scans it again.

## Status

`node self-host/setup.mjs status` lists each part and whether the server's address answers.

## Remove my Relay Everything

`node self-host/setup.mjs remove` lists what it would delete. Show the person that list. It deletes every note, recording, health sample and place, and it can't be undone. Run `remove --yes` only after the person says yes in the chat.

## If something fails

- `result=refused` from `check` or `install`: fix each `missing` line, then run it again. Nothing was made.
- `result=failed`: the line before names the step. Run the same command again: each step that is done is skipped.
- `install` writes `self-host/wrangler.jsonc`, `self-host/wrangler.mcp.jsonc` and `self-host/wrangler.spaces.jsonc`, which `update` and `status` read. Keep them. Git ignores them.
