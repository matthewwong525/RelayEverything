# Design

## Context

A fresh WongStack 48.2.0 install on the Artifacts route: `origin` is the `relay-ring` repository in Cloudflare Artifacts, and `/ship` publishes by `publish-artifacts.sh` onto `main`. GitHub is signed in on this computer as `matthewwong525` (`repo` scope) but plays no part in the ring's own delivery.

## Goals / Non-Goals

**Goals:** bring the ring files in as plain files; start `mobile/`; mirror `mobile/` of each published `main` to the public `relay-app` repository, refusing secrets.

**Non-Goals:** a Flutter toolchain, CI for the app, a submodule or subtree link between the two repositories.

## Decisions

- **The mirror reads git, not the folder.** `scripts/publish-relay-app.mjs` exports `mobile/` at a commit (default `origin/main`) with `git archive`, so ignored and untracked files (`.env`, build output) can never leave. It strips the `mobile/` prefix, so the public repository's root is the app.
- **A guard before any push.** It refuses the whole copy when a path looks private (`.env*` other than `.env.example`, key stores and signing files, `key.properties`, Firebase config, a `notes/` folder or `*.private.*`) or a file's text holds a key pattern or any value from the primary `.env`. It names the file, never the value.
- **One commit per publish.** A fresh clone of `relay-app` gets its tree replaced; unchanged trees push nothing. The message names the ring's short commit only. Missing repository → `gh repo create --public` once.
- **Run by rule.** `AGENTS.md` (outside the WongStack block) tells the assistant to run the script after `/ship`'s `finish` merges, and to report its one result line. Alternative rejected: a check-runner stage, which would need a GitHub key inside Cloudflare.
- **Vendor as plain files.** `vendor/nordic-lib-kicad/` is copied without `.git`; `vendor/README.md` records source and commit. Its own `.gitmodules` is inert below the repository root.
- **Ignore STL exports** with `*.stl`, plus Python's `__pycache__/`.

## Risks / Trade-offs

- A publish made without the assistant (by hand) skips the mirror; the next run catches up, since it copies the whole folder.
- The key-pattern guard can block a false positive; the fix is to move the text out of `mobile/`, never to loosen the guard silently.
