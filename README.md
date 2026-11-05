# Relay

Relay gets your notes, health and location off your phone and devices, into a place you choose, where your own AI can read them. Read more and get started at [relayeverything.com](https://relayeverything.com), from [what you need](https://relayeverything.com/start/what-you-need/).

A ring is one way to take a note: hold the band, talk, and let go. A Pebble Index ring works today. The Relay ring, in [`cad/`](cad/) and [`pcb/`](pcb/), is in design.

## What is here

| Folder | What it holds |
|---|---|
| [`app/`](app/) | The Relay server and its private web app, a Cloudflare Worker |
| [`mobile/`](mobile/) | The phone app for Android and iPhone, in Flutter |
| [`site/`](site/) | The public website at relayeverything.com |
| [`cad/`](cad/) | The ring's 3D models, in OpenSCAD |
| [`pcb/`](pcb/) | The ring's board, in KiCad |
| [`vendor/`](vendor/) | Copied libraries, each with its own license |
| [`self-host/`](self-host/) | Run your own Relay server in your own Cloudflare account: [`SETUP.md`](self-host/SETUP.md) |
| [`schema/`](schema/) | The database's tables and migrations |
| [`scripts/`](scripts/) | The tools that check, build and publish |
| [`openspec/`](openspec/), [`wiki/`](wiki/) | The plans, and how the project is made |

## Run the checks

Each pull request runs the checks on GitHub Actions. To run them on your computer, install Node.js (the version is in [`.nvmrc`](.nvmrc)), then, from the top folder:

```sh
(cd app && npm ci && npm test)                        # the server and web app
(cd site && npm ci && npm test)                       # the website
(cd mobile && flutter analyze && flutter test)        # the phone app
node scripts/public-check.mjs                         # no keys or private notes
```

To build the phone app yourself, read [`mobile/README.md`](mobile/README.md).

## Contribute

Open a pull request. Its checks run with none of the project's keys, and nothing deploys from it. Never commit a key, a `.env` file or a signing file: the checks refuse them.

## License

[MIT](LICENSE), except [`vendor/`](vendor/), where each library keeps its own license.
