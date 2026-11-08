# Design

## Context

See proposal.md, *Why*. Three things shape the build:

- `self-host/setup.mjs` finds the app as `join(HERE, '..', 'app')` and imports `../scripts/*.mjs`. Its tests run from `app/package.json`'s `test` line as `node --test ../self-host/*.test.mjs`. `app/vite.config.ts` reads `../self-host/wrangler.template.jsonc` for a Relay-only build.
- A person's install keeps git-ignored files in `self-host/`: `wrangler.jsonc`, `wrangler.mcp.jsonc`, `wrangler.spaces.jsonc`, and `.env` with the Cloudflare key. After a pull, git leaves them in the old folder.
- `schema/`, `scripts/`, `.agents/`, `paseo.json` and the `.codex` link are WongStack payload: `/wong-sync` writes them by path.

## Goals / Non-Goals

**Goals:** the top level holds only folders a visitor recognizes; every check passes; an old install updates unchanged.

**Non-Goals:** a history rewrite; any change to WongStack payload paths.

## Decisions

- **`app/self-host/`, not `scripts/self-host/`.** The tool installs the app's Workers and reads the app's configs, so it sits beside them. `scripts/` is WongStack payload. Paths become `join(HERE, '..')` for the app, `../../scripts/` for imports, `self-host/*.test.mjs` in the test line, and `./self-host/wrangler.template.jsonc` in Vite. The command a person's AI runs becomes `node app/self-host/setup.mjs`, from the repository root as before.
- **Carry an old install over in `setup.mjs`, not in the guide.** On any command, when `app/self-host/<file>` is missing and `<repo>/self-host/<file>` exists, `setup.mjs` moves it across, for the four ignored files, and prints one `moved=` line. Then it removes the old folder only when empty. A step in SETUP.md would depend on the AI reading it; the move in code runs every time. A test covers: old files present → moved and used; both present → the new one wins and the old stays.
- **The website's ring pages stay as pages.** `board.md` and `models.md` keep their words and pictures, and drop the *on GitHub* links. No link to an old commit: the ring is in design and not offered for download (the website spec already offers no `cad/` or `pcb/` download).
- **The app's lint and unused-code checks.** `.mjs` files in `app/self-host/` may now fall under app's ESLint, `knip` and `jscpd`. Make them pass as they stand; if a rule fires on code the move did not change, add the folder to that tool's ignore list with a comment, never loosen a rule for the whole app.
- **The README.** Keep its sections (what it is, what is here, run the checks, contribute, license); cut the ring paragraph; the table lists `app/` (with *Run your own server* in `app/self-host/`), `mobile/`, `site/`, `plugin/`, `brand/`, `schema/`, `scripts/`, `openspec/` and `wiki/`. The plugin is in the table today only by omission; add it.

## Risks / Trade-offs

- [An old install's AI reads the old SETUP.md path] → the website page and the README name the new path; `setup.mjs`'s usage line names it too.
- [Another open workspace edits `AGENTS.md`, `wiki/open-source.md` or `README.md`] → text-only conflicts; the later save merges them by hand.
- [The site's ring pictures can no longer be rebuilt here] → they are finished pictures; a new model ships with its own pictures.

## Migration Plan

Merge, then publish the website and the server by the usual after-publish commands. No data moves.
