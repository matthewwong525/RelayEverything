# Tasks

## 1. The copy's sources

- [x] 1.1 Move every script and skill off `CLAUDE_PLUGIN_ROOT` (design §2): skills call `node "$(git rev-parse --show-toplevel)/.agents/relay/bin/…"`; `appOf` in `lib/headless.mjs` drops `PLUGIN_ROOT`. Rename the skills to `relay-<name>` in their frontmatter and text, and change `/relay:` to `/relay-` everywhere a person reads it. Update `plugin/test/skills.test.mjs`, `headless.test.mjs`, and the tests that name commands; all pass.
- [x] 1.2 Add `plugin/hooks/claude.json` and `plugin/hooks/codex.json` (design §2), the same events and time limits as `hooks/hooks.json`. Test in `plugin/test/hooks.test.mjs`: both name the same events and scripts as `hooks.json`.

## 2. Install

- [x] 2.1 Write `plugin/install.mjs` (design §3): not a git project → refuse; copy present → no change and the update hint; else copy, `RELEASE`, links (a taken name skipped and reported), hook groups merged. Test in `plugin/test/install.test.mjs` on a temp git project: files and links made; the person's own hooks and skills kept; a second run changes nothing; a taken skill name skipped; no file under `.agents/relay/` holds a key after a connected computer installs.
- [x] 2.2 Write the site's *Install* page (`site/src/content/docs/install.md`, served at `/install/`): the prompt to copy, then the AI's steps (design §3), the per-project note, and Codex's trust step. Change `site/src/content/docs/connections/claude-code.md` and `connect-your-ai.md` to point there. Run the site's build and `node --test scripts/product-name.test.mjs`.

## 3. Update

- [x] 3.1 Write `plugin/update.mjs` with `check`, `plan`, `apply` (design §5), taking a releases folder in tests in place of GitHub. Test in `plugin/test/update.test.mjs`: only-upstream, only-copy and both-changed files; a clean both-changed merge; a clash with markers reported and not written by `plan`; an added and a deleted file; `apply` rewrites `RELEASE` and links a new skill; `up_to_date`.
- [x] 3.2 Write `plugin/skills/update/SKILL.md` (`/relay-update`): check, show the plan in plain words, walk each clash with *keep mine / keep the release's / both*, apply only on a yes. Add it to `skills.test.mjs`.

## 4. The last plugin

- [x] 4.1 In `plugin/bin/hook.mjs`, step aside when the plugin runs from the plugin cache and the project has `.agents/relay/RELEASE`; show the move message once per computer in a project with no copy (design §6). Test in `hook.test.mjs`: a project with both sends once; the message shows once.
- [x] 4.2 Write `plugin/skills/move/SKILL.md` (`/relay:move`, only in the plugin's manifest list) that runs `install.mjs --into <project>` and, on a yes, the two remove commands. Set the plugin's version to 0.7.0 and the copy's release to 0.8.0 in `plugin/.claude-plugin/plugin.json` and the Codex manifest.

## 5. Docs and release

- [x] 5.1 Rewrite `plugin/README.md` for the copy: install, update, per-project saving, where per-computer files live. Change `wiki/stack/relay-chats.md`'s release step to add the `relay-v<version>` tag (design §4), and `wiki/stack/relay-knowledge-web.md`'s paths. In `AGENTS.md`'s Relay Everything block, change the `/relay:` command names to `/relay-` and *the plugin* to *the copy*.
- [x] 5.2 Add `plugin/install.mjs`, `plugin/update.mjs` and the new site page to `scripts/product-name.test.mjs`'s list; run `node scripts/public-check.mjs`.

## 6. Check it

- [x] 6.1 Run the plugin tests and `npm test` in `app/`; all pass.
- [x] 6.2 On staging (the plugin trial in the `relay-plugin` memory): in a temp git project, paste the install prompt into `claude -p` with the release taken from this branch; see the copy, links, hooks and the sign-in link; connect the test person; chat and see the chat saved once with the plugin also loaded; edit a skill, make a fake newer release, run `/relay-update`, and see the edit kept and a clash asked. Then `/save` and check the preview.

## 7. Review fixes

- [x] 7.1 In each plugin skill that runs `.agents/relay/bin/…`, when the project has no `.agents/relay/`, run the same script from the folder two levels above the SKILL.md (no `CLAUDE_PLUGIN_ROOT`), and never install the copy unasked: offer `/relay:move`. Test in `skills.test.mjs`: no skill tells the AI to install without the person's ask.
- [x] 7.2 `plugin/bin/relay.mjs`: match the chat-only key refusal by its first sentence, not the whole text, and test it against the server's exact string from `app/worker/apps/relay/caller.ts`.
- [x] 7.3 Change `/relay:connect` to `/relay-connect` in `app/worker/apps/relay/sign-in/computer.ts`, `caller.ts` and `device.ts` and their tests (`device.test.ts`, `relay-mcp/auth.test.ts`); run `npm run relay:api-doc` in `app/`. Leave `mobile/` as is.
- [x] 7.4 Design §1: `RELEASE` holds the commit or the tag. Spec scenario *A project with no copy* and the install page: a project with no copy and no plugin saves nothing; the plugin keeps saving until it is removed.
- [x] 7.5 Run the plugin tests and `npm test` in `app/`; all pass.

