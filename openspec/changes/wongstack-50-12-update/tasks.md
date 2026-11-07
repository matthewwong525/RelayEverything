## 1. Copy the unchanged and new units

- [x] 1.1 Copy the 17 installed-equivalent units and the 2 added units from the source at `2acdf24b018a3596186316cc29a91ccfb40384b7`, by the design's lists.

## 2. Take the upstream browser

- [x] 2.1 Copy upstream `.claude/skills/browser/SKILL.md`, `scripts/browse.mjs`, `scripts/browser-server.mjs` and `scripts/forwarder.mjs`; delete `scripts/server.mjs` and `scripts/forwarder.test.mjs`; verify `grep -rn "server.mjs\|languageLine\|network off" .claude/skills/browser` finds nothing.
- [x] 2.2 Merge `wiki/development/browser-proxy.md`, `browsing.md`, `browser-window.md` and the `wiki/development/README.md` link text by the design, keeping the *When your turn holds the browser* section and adding the keep-the-proxy-on line.

## 3. Merge the access test

- [x] 3.1 Merge `app/worker/employee-access/login-management.test.ts`: add `admittedEmails` and the no-session-time test; keep the *Relay devices* lines.

## 4. Verify

- [x] 4.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target . --source /root/.cache/wong-stack/WongStack --from 1d14a762d2bc132ed78f054aec8adeca3cb4e406`; take every missing hunk, or name each one left out on purpose.
- [x] 4.2 Run `npm test` in `app/` and `node scripts/public-check.mjs --tree`; verify both pass with no check loosened.
- [x] 4.3 Run `node .claude/skills/browser/scripts/browse.mjs status` and `browse.mjs proxy`; verify `BROWSE_PROXY=on` and a `BROWSE_NETWORK=` line, with no restart.
- [ ] 4.4 Run `/save` and verify the pull request's checks pass.

## 5. Install record

- [x] 5.1 Set `.claude/.wong-stack.json` `version` to `50.12.0` and `commit` to `2acdf24b018a3596186316cc29a91ccfb40384b7`, keeping every other key; verify the JSON parses and the preflight reports `status: current`.
