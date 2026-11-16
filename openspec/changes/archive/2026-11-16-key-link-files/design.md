# Design

## Context

The key link is WongStack's [hand-over](../../../.agents/skills/browser/skills/hand-over/references/key-link.md) page. This repo's `keys.mjs`, `keys-page.mjs` and `keys-page.html` are byte-equal to WongStack's `main` (`.agents/plugins/browser/skills/hand-over/scripts/`); `key-link.md` differs only in local wording. WongStack owns the tests (`scripts/tests/keys.test.mjs`, `scripts/tests/keys-page.test.mjs`) and the spec (`openspec/specs/secrets-convention/spec.md`, *The key page takes a paste, a long key, or a key file*). This repo runs no test on these files.

Today: `LIMITS.value = 4096` (stored form, `\n` counted as two characters), `LIMITS.body = 16 * 1024` (413 past it), and the page's `FILE_LIMIT = 16 * 1024` with `file.text()`, which turns a binary file's bytes into U+FFFD characters.

## Goals / Non-Goals

**Goals:** a Developer ID `.p12` saves through *or pick a file*, as the base64 line the Mac workflow decodes; the same edit in WongStack, with its tests, spec delta and changelog entry.

**Non-Goals:** a separate file-upload route; a lower limit for Worker secrets; saving `MACOS_DEVID_CERT_P12` itself (the person adds it on GitHub for now).

## Decisions

- **Limits.** `LIMITS.value = 32 * 1024`, `LIMITS.body = 128 * 1024`, page `FILE_LIMIT = 24 * 1024`. 24 KB of bytes is 32 KB of base64, so any accepted file fits one value. 32 KB stays under GitHub's 48 KB secret limit. A body holds about four full keys; more gives the existing *That's too much at once* message. Alternative: 64 KB a key; rejected, it passes GitHub's limit and no key needs it.
- **Text or not.** A new exported `fileValue(bytes)` in `keys-page.mjs` returns `{ text }` when `new TextDecoder('utf-8', { fatal: true })` decodes the bytes and they hold no zero byte, else `{ base64 }` (the bytes base64-encoded in chunks, through `btoa`). `pickFile` reads `file.arrayBuffer()` in place of `file.text()`. An empty file still says *That file is empty.* Alternative: decide by extension (`.p12`, `.der`, `.cer`); rejected, it misses unnamed binary files and a phone may hide the extension.
- **The held line.** A text file keeps `heldLabel(name, text)`: name and line count. A base64 file shows `<name> · <size>, saved as base64`, with the size in KB rounded up, through a new `fileLabel(name, bytes)` beside `heldLabel`. Neither shows content.
- **The server.** No new code: base64 is one line of `BARE` characters, so `cleanValue` keeps it and `formatLine` writes it unquoted.
- **Order.** Build and test in a WongStack worktree first, because the tests live there; copy the three script files here byte-equal; apply the key-link sentence to both copies of `key-link.md`. The upstream pull request carries a `## Next (minor) — …` changelog entry and a `secrets-convention` MODIFIED delta that adds a binary-file scenario. WongStack's own `/ship` numbers the release.

## Risks / Trade-offs

- A Worker secret over Cloudflare's 5 KB limit saves to `app/.dev.vars` but fails at `npm run secrets:push`, which names it. The guide says so in one clause.
- A Latin-1 text file that is not valid UTF-8 arrives as base64. Rare for a key file; the label says *saved as base64*, so the person sees it.
- Until WongStack merges, this repo's copy is ahead of upstream. `/wong-sync` then sees equal files; if upstream changes the wording in review, the next sync brings it down.
