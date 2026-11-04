# Proposal

**Status:** ready-to-ship
**Branch:** set-up-relay-ring
**Open questions:** none

## Why

The Relay ring needs one home: its 3D models, circuit board, parts library and phone app in one private project, with checks, previews and publishing in Matthew's Cloudflare account. The phone app should also be open to the world, so each published change sends a copy of just the app to a public GitHub repository.

## What Changes

- **WongStack runs this project.** The project gets the usual skills, wiki, starter site and memory, kept in Cloudflare with no GitHub repository for the ring itself.
- **The ring files move in.** The 3D models, the circuit board and Nordic's parts library come over from the old folder. Printable STL exports stay out of the saved history, since the models rebuild them.
- **A phone app folder starts.** `mobile/` holds a short README until Flutter is installed on this computer.
- **Publishing also updates the public app.** Each publish copies only the app folder to a public GitHub repository, with no keys or private notes.
  ```mermaid
  flowchart TD
    A["publish"] --> B["relay-ring main"]
    B --> C["copy mobile/ only"]
    C --> D["guard: no keys, no notes"]
    D --> E["github.com/matthewwong525/relay-app"]
  ```

Non-goals: building the Flutter app itself, ordering prints from JLC (that stays in the chat Relay ring), and putting the ring's private files anywhere public.

## Capabilities

### New Capabilities
- `relay-app-publish`: copying the published `mobile/` folder, and nothing else, to the public `matthewwong525/relay-app` repository, refusing keys and private notes.

### Modified Capabilities

## Impact

- New: `cad/`, `pcb/`, `vendor/nordic-lib-kicad/`, `mobile/`, `scripts/publish-relay-app.mjs` and its test, a project rule in `AGENTS.md`, `.gitignore` lines.
- Cloudflare (account 040f88e2bf4f25fb0b91b7cb24f3d442): the `relay-ring` Artifacts repository, check runner, app Workers and databases, memory store, knowledge repository and deploy token, made by setup's provisioning.
- GitHub: a new public repository `matthewwong525/relay-app`.

## Decision log

- **2026-11-04** — Asked which route to install by → chose the Artifacts route: code in Cloudflare, no GitHub repository for Relay.
- **2026-11-04** — Asked which Cloudflare account → chose Matthewwong525@gmail.com's Account (040f88e2bf4f25fb0b91b7cb24f3d442), reusing the WongOS token.
- **2026-11-04** — Asked whether to set up on the paid plan → chose yes; the account is already on Workers Paid.
- **2026-11-04** — Asked how the phone app reaches the public → chose copying only `mobile/` to a new public repository matthewwong525/relay-app on each publish, with no sub repository and no keys or private notes.
- **2026-11-04** — Asked what to do with STL exports → chose keeping them out of git; the `.scad` models rebuild them.
- **2026-11-04** — Asked how to bring in the Nordic library → chose plain files with no nested `.git`, noting its source at https://github.com/hlord2000/nordic-lib-kicad commit 05a4dae.
- **2026-11-04** — Assumed: the copy runs on this computer right after each publish, from a project script the assistant runs by an `AGENTS.md` rule, because WongStack's publish has no hook and the check runner holds no GitHub credential.
- **2026-11-04** — Assumed: each publish becomes one commit in relay-app with the files exactly as on `main`, because the public history needs no private commit messages.
- **2026-11-04** — Assumed: the old folder's PNG renders and the board outline DXF come in with `cad/`, because only STL exports were named as rebuildable.
- **2026-11-04** — Assumed: saved the install as built, with Cloudflare provisioned (private site, memory with transcripts, check runner) and local checks passing; relay-app is created on the first publish, because the script creates it only when it has something to push.
- **2026-11-04** — Assumed: archived for the first publish, because every task is done and the branch passed its checks.
