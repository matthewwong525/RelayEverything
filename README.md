# Relay Everything

Relay Everything gets your notes, health and location off your phone and devices, into a place you choose, where your own AI can read them. Read more and get started at [relayeverything.com](https://relayeverything.com), from [what you need](https://relayeverything.com/start/what-you-need/).

## What is here

| Folder | What it holds |
|---|---|
| [`app/`](app/) | The Relay Everything server and its private web app, a Cloudflare Worker. To run your own server in your own Cloudflare account, read [`app/self-host/SETUP.md`](app/self-host/SETUP.md) |
| [`mobile/`](mobile/) | The phone app for Android and iPhone, in Flutter |
| [`site/`](site/) | The public website at relayeverything.com |
| [`plugin/`](plugin/) | The Claude Code plugin, which saves each chat to your Relay Everything server |
| [`brand/`](brand/) | The logo, and the script that makes the app and website icons |
| [`schema/`](schema/) | The database's tables and migrations |
| [`scripts/`](scripts/) | The tools that check, build and publish |
| [`openspec/`](openspec/), [`wiki/`](wiki/) | The plans, and how the project is made |

## Run the checks

Each pull request runs the checks on GitHub Actions. To run them on your computer, install Node.js (the version is in [`.nvmrc`](.nvmrc)), then, from the top folder:

```sh
(cd app && npm ci && npm test)                        # the server, web app and plugin
(cd site && npm ci && npm test)                       # the website
(cd mobile && flutter analyze && flutter test)        # the phone app
node scripts/public-check.mjs                         # no keys or private notes
```

To build the phone app yourself, read [`mobile/README.md`](mobile/README.md).

## Contribute

Open a pull request. Its checks run with none of the project's keys, and nothing deploys from it. Never commit a key, a `.env` file or a signing file: the checks refuse them.

## License

[MIT](LICENSE).
