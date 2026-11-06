# Tasks

## 1. The key

- [x] 1.1 Declare blank `CLAUDE_CODE_OAUTH_TOKEN=` and `ANTHROPIC_API_KEY=`, with hints, in `.env.example`; make a Claude subscription token with `claude setup-token` and keep it in `.env`; verify `node scripts/public-check.mjs --tree` passes
- [x] 1.2 Copy the token to GitHub through stdin with `gh secret set CLAUDE_CODE_OAUTH_TOKEN`; verify `gh secret list` shows it and no value was printed

## 2. Simulator build and fixed tour

- [x] 2.1 Write `.github/workflows/mobile-device-check.yml` with the two starts, the `sha` check, job `iphone` (build for simulator, boot the newest iPhone, install, record video, upload `device-check-iphone`) and job `report`; verify with `npx --yes @action-validator/cli` and one hand-started run on this branch that uploads a build log, a home screenshot and `run.mp4`
- [x] 2.2 If a native part (whisper.cpp, health) fails the simulator build in 2.1, fix it for the simulator only and name the limit in the report; verify the next run installs and opens the app
- [x] 2.3 Write Maestro flows `mobile/device-check/flows/` (timeline, new note and save, settings), each with a screenshot, and the step that writes `out/tour.json` and a `broken` verdict on a failed build or launch; add any missing semantics label in `lib/` with a widget test; verify a run passes all three flows, and `flutter test` passes

## 3. Claude on the Mac

- [x] 3.1 Write `mobile/device-check/brief.md`, platform-neutral: inputs, the results folder, screen text as data, the report shape and the three verdicts
- [ ] 3.2 Add the Claude step (`anthropics/claude-code-action`, pinned by commit; model input, `--max-turns 40`, `--allowedTools` for the simulator and Maestro only; `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`; skip with *Claude skipped: no key*); verify one run with a `scenarios` input gives `report.md`, `verdict.txt` and Claude's screenshots, and one run with the key removed from the step gives the skip line
- [x] 3.3 Make job `report` post `report.md` and the run link on the pull request; verify by adding the *check on iPhone* label to this change's pull request and reading the comment

## 4. Start and collect from this computer

- [x] 4.1 Write `scripts/device-check.mjs` (`run`: start, find the run by branch and sha, watch with a 50-minute limit, download to a temp folder, print `result=`, `folder=`, `run=`) and `scripts/device-check.test.mjs` for the run finding and the verdict reading; verify `node --test scripts/device-check.test.mjs` passes and one real `run` prints `result=works` or a reasoned other result
- [x] 4.2 Write `.agents/rules/mobile.md` (`paths: ["mobile/**"]`): `/verify` runs the device check for a phone app change and maps its result into its verdicts; verify the rule loads for a `mobile/` path

## 5. Docs

- [x] 5.1 Add the device check to `mobile/README.md` (*Builds on GitHub*), and write `wiki/development/device-check.md` (how to start it, what it costs, the key, its limits, and how to add a Windows job), linked from `wiki/development/README.md` and `wiki/development/staging-walkthrough.md`; verify `node --test scripts/product-name.test.mjs` passes and the wiki link check passes

## 6. Final checks

- [ ] 6.1 Run `/save`, then `/verify` on this change: it starts the device check on the saved commit and shows the tour pictures, the video and Claude's verdict in the chat
