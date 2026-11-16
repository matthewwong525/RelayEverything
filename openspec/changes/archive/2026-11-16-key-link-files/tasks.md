# Tasks

## 1. WongStack: the key link (upstream first, where the tests live)

- [x] 1.1 Make a fresh worktree of `/root/WongStack` from `origin/main` on a new branch `key-link-files`; never work in `~/.cache/wong-stack/`
- [x] 1.2 In `.agents/plugins/browser/skills/hand-over/scripts/keys.mjs`, set `LIMITS.value = 32 * 1024` and `LIMITS.body = 128 * 1024`
- [x] 1.3 In `keys-page.mjs`, set `FILE_LIMIT = 24 * 1024`; add exported `fileValue(bytes)` (strict UTF-8 with no zero byte → `{ text }`, else `{ base64 }`) and `fileLabel(name, bytes)` (`<name> · <n> KB, saved as base64`); make `pickFile` read `file.arrayBuffer()` and hold the text or the base64 line
- [x] 1.4 In `scripts/tests/keys-page.test.mjs`: `fileValue` on JSON, PEM, `.p12`-like bytes, a zero byte and invalid UTF-8; a picked binary file is held as base64 with `fileLabel` and sent as one line; the over-limit test uses the new `FILE_LIMIT`
- [x] 1.5 In `scripts/tests/keys.test.mjs`: a 6,000-character base64 value saves bare and reads back equal; the limit tests follow `LIMITS` (they already read it, so check they pass unchanged)
- [x] 1.6 In `references/key-link.md`, add one sentence: a key holds up to 32 KB; a picked file that is not text is saved as one base64 line; a Worker secret holds at most 5 KB
- [x] 1.7 Open a WongStack OpenSpec change with a MODIFIED delta on `secrets-convention`'s *The key page takes a paste, a long key, or a key file*: keep its scenarios, add *A binary key file* (a `.p12` saves as base64 and reads back as the same bytes)
- [x] 1.8 Add a `## Next (minor) — The key link takes longer keys and any file` entry to `CHANGELOG.md`, with an **Updating.** line: nothing to do by hand

## 2. This repo: the same edit

- [x] 2.1 Copy WongStack's `keys.mjs`, `keys-page.mjs` and `keys-page.html` over this repo's `.agents/skills/browser/skills/hand-over/scripts/`, and check them byte-equal with `diff`
- [x] 2.2 Add 1.6's sentence to this repo's `references/key-link.md`, in its own wording around it

## 3. Checks

- [x] 3.1 In the WongStack worktree, run `node .github/scripts/checks.mjs --worktree` and `openspec validate --strict --no-interactive` for its change; fix any failure
- [x] 3.2 Make a 4 KB random binary file as a stand-in `.p12`, run `fileValue` on its bytes, and check `cleanValue` and `formatLine` keep the base64 line whole and `base64 --decode` gives the same bytes; no real certificate is used
- [x] 3.3 Here, run `node scripts/public-check.mjs` and `cd app && npm test`
- [x] 3.4 Ask, then open the WongStack pull request (outward), its body arguing why every WongStack repo wants it, and report its link; `/save` this repo's change after it
