---
title: Run your own Relay Everything server
description: Make your own Relay Everything server in your own Cloudflare account, with one request to your AI. Relay Everything's apps only add data to it.
---

Your Relay Everything server keeps what your phone and Claude Code send. You make it in your own Cloudflare account, so it and its data are yours. Relay Everything's apps only add data to it: they can't read it back. You read it on your Relay Everything page, and your own AI reads it through your AI connector.

## Make it

Paste this request into Claude Code or another coding AI:

```text
Install Relay Everything from https://github.com/matthewwong525/RelayEverything.
Read and follow app/self-host/SETUP.md there.
```

The AI follows Relay Everything's setup guide. It asks you to make a Cloudflare key and save it in a file on your computer, never in the chat. Then it makes your server and gives you its address. It takes about 10 minutes.

:::note
Cloudflare's free plan is enough. Cloudflare asks you to turn on two parts once, in its dashboard: R2, for recordings, and Zero Trust, for your login. Both are free, but Cloudflare can ask for a payment card before it turns on R2.

The [knowledge web](../../api/knowledge-web/) needs Cloudflare Artifacts, on the Workers Paid plan. On the free plan, your server works the same, with your memory of facts, but with no knowledge web: a computer that asks for it is told that it is not set up.
:::

## What you get

| Your server has | Your server does not have |
|---|---|
| The Relay Everything server: notes, recordings, health, places and AI chats, each person's in their own space | The tools that build Relay Everything |
| Your Relay Everything page, with your email as its only login | A login for anyone else, until you turn sign-up on |
| A key for each phone, Claude Code computer and script | A way for a key to read your data |
| Your AI connector, so your own AI reads your data | A way in for Relay Everything's makers |
| [Webhooks](../../connections/your-database/) to your own database | A cost, on the free plan |

## Your devices

Sign in on your Relay Everything page with your server's own login. You read and write your notes there. Each Claude Code or Codex computer gets its own key when you type `/relay-connect https://<your-relay-server>`: [Save AI chat transcripts](../../connections/claude-code/#connect-the-computer). For your own script, open **Settings**, then **Account**, and under **Advanced** click **API keys**, then **Add an API key**. A key adds data, and an API key also reads through the web API: [Keys](../../api/keys/#what-a-device-key-reaches).

The Relay Everything app on a phone signs in only to the shared Relay Everything server, so on your own server you use the page and Relay Everything in your Claude Code or Codex projects. A phone that was already connected to your server keeps sending there.

## Who can sign in

Your server keeps Cloudflare Access, the login it was made with: `RELAY_SIGN_IN` is `access`. Only your email gets an account, and your data goes in your own space. To let other people sign up, set `RELAY_SIGN_UP` to `open` in your server's settings, and let their emails through your Cloudflare Access login. Each new person then gets their own space, and you can't open it: [Privacy](../../privacy/).

Your server shows no contact address until you set one. To give the people on your server an address for questions and privacy requests, set `RELAY_CONTACT_EMAIL` to it in your server's settings. Each person's account card then shows it. Your Cloudflare Access login comes before the page, so the sign-in screen does not. Relay Everything's own terms and policies cover only the shared server: on your server, you answer those requests.

## Take email

Your server can make [email notes](../../app/email/) too. It is off until you set it up, and it needs a domain on Cloudflare. Ask your AI *turn on email notes for my Relay Everything server*, or do these steps:

1. Pick a mail domain on Cloudflare for your server, such as a subdomain of your own domain.
2. In the Cloudflare dashboard, turn on **Email Routing** for that domain, and add a catch-all rule that sends each mail to your server's Worker.
3. Set two secrets on your server's Worker: `RELAY_INBOX_MAIL_DOMAIN`, the mail domain, and `RELAY_INBOX_HMAC_KEY`, a key made with `openssl rand -base64 32`. Keep a copy of the key: a new key stops every notes address. An update keeps both.

Old kept mail is deleted when new mail comes, because your server has no daily job.

## Update it

Ask your AI *update my Relay Everything*. It gets the newest version of Relay Everything, applies its database changes, then puts it live. Your data stays. If a database change fails, your server stays as it was.

If you made your server when the setup guide was in a top-level `self-host/` folder, the update finds your settings and Cloudflare key there and moves them to `app/self-host/`. You do nothing.

If your server is from before spaces, the update also makes your spaces Worker, `<name>-spaces`, and your own account. It doesn't move your old data: the update removes the old shared tables, and the notes in them. The old keys stop too: connect each computer again with `/relay-connect`, and make each script a new key with **Add an API key**.

## Remove it

Ask your AI *remove my Relay Everything*. It shows what it will delete and asks first: the server, its spaces with their notes, recordings, health and places, and its keys. This can't be undone.
