# Longer keys and any file through the private key link

**Status:** ready-to-ship
**Branch:** dry-fireant
**Open questions:** none

## Why

Today the private key link refused the Mac app's signing certificate with *Couldn't save this one; check it and try again*. The link takes at most 4,096 characters a key, and the certificate is about 5,000 to 6,000. Its *pick a file* button also reads every file as text, so a certificate file (`.p12`), which is not text, would arrive broken.

## What Changes

- **A key can be up to 32,000 characters.** That is eight times today's limit, and holds a signing certificate, a long key file, or a chain of certificates. GitHub's own limit for one secret is 48 KB, so each saved key still fits there.
- **Any file goes through *or pick a file*.** A text file, such as a JSON key file, works as today. A file that is not text, such as a `.p12` certificate, is changed on your phone or computer to base64: one line of plain letters and digits, which is the form the Mac build reads back. The page shows the file's name and size, never its content. A file can be up to 24 KB.
  ```screen
  <div class="card col gap phone">
    <h3>Mac Developer ID certificate</h3>
    <p class="muted">MACOS_DEVID_CERT_P12</p>
    <p>Paste it here</p>
    <p>Certificates.p12 · 4 KB, saved as base64</p>
    <div class="row gap"><button class="btn-ghost">Pick another file</button><button class="btn-ghost">Remove</button></div>
    <div class="row gap"><span class="grow"/><button class="btn-primary">Save and continue</button></div>
  </div>
  ```
  No real picture: the key page opens only through a live private link.
- **The same change goes to WongStack.** I send it to WongStack as its own pull request, so every project that uses WongStack gets it, and the next update here changes nothing.

**Not in this change:** adding the certificate itself. For now you add it on GitHub's own secrets page, as the Mac in-app updates plan says. After this change, the key link can take it too.

## What the build needs

- **WongStack access**: Ready. Its copy on this computer is up to date, and this account can open a pull request there.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None in this repo. The requirement *The key page takes a paste, a long key, or a key file* belongs to WongStack's `secrets-convention` spec, so the upstream pull request carries its delta.

## Impact

- `.agents/skills/browser/skills/hand-over/scripts/keys.mjs`: `LIMITS.value` and `LIMITS.body`.
- `.agents/skills/browser/skills/hand-over/scripts/keys-page.mjs`: `FILE_LIMIT`, how a picked file is read, and its held label.
- `.agents/skills/browser/skills/hand-over/references/key-link.md`: one sentence on files and sizes.
- Upstream, in WongStack: the same three files under `.agents/plugins/browser/skills/hand-over/`, `scripts/tests/keys.test.mjs`, `scripts/tests/keys-page.test.mjs`, `openspec/specs/secrets-convention/spec.md` (by a change's delta), and a `CHANGELOG.md` entry.

## Decision log

- **2026-11-16** — Assumed: the new limit is 32,768 characters a key and 128 KB a request, because a Developer ID `.p12` is about 6,000 characters as base64, and GitHub holds at most 48 KB a secret.
- **2026-11-16** — Assumed: a picked file that is not text is sent as base64 on one line, because `.env.example` declares both `.p12` keys as base64 and the Mac workflow decodes them with `base64 --decode`.
- **2026-11-16** — Assumed: the page tells text from other files by reading the bytes as UTF-8, strictly, with no zero byte, because a file's name or type says nothing reliable on every phone.
- **2026-11-16** — Assumed: this repo's copy changes in this change, word for word as upstream's, because the person needs it here now, and `/wong-sync` then finds no difference.
- **2026-11-16** — Assumed: this change carries no spec delta here (`skip_specs: true`), because the key link's spec lives only in WongStack; a local copy would be a second home for one rule.
- **2026-11-16** — Assumed: one limit for every key, with no lower one for Worker secrets, because only `app/.dev.vars` keys reach Cloudflare, whose 5 KB limit `npm run secrets:push` reports by itself; the guide says so.
- **2026-11-16** — Assumed: archived for `/ship`; the same change went to WongStack as https://github.com/matthewwong525/WongStack/pull/606, shipped in its own repo.
