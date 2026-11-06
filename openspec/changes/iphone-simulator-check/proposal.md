# Proposal: Check the iPhone app on a Mac in the cloud

**Status:** built, live checks on GitHub next
**Branch:** ios-simulator-verification-linux
**Open questions:** none

## Why

The Relay Everything phone app is for iPhone first, but this computer runs Linux and can't start an iPhone simulator. Today the only way to see a change on an iPhone screen is to wait for TestFlight and try it on your own phone. Matthew asked for a check that runs on a Mac in the cloud, with Claude in it, so `/verify` can show the app on an iPhone before a change goes live.

## What Changes

**What you get**

- **An iPhone check on a Mac from GitHub.** When a change touches the phone app, the check builds the app for the simulator, starts an iPhone simulator, and opens the app. GitHub's Macs cost nothing because the repository is public. A run takes about 15 minutes.
  ```mermaid
  flowchart TD
    A["/verify here"] --> M[Mac on GitHub]
    M --> S[Build, open on iPhone sim]
    S --> F[Fixed tour]
    F --> C[Claude tries the change]
    C --> R[Report + pictures]
    R --> A
  ```
- **A fixed tour of the main screens every time.** A short script opens the timeline, writes a note, saves it, and opens Settings. It takes a screenshot of each screen. This part uses no AI, so it costs nothing and gives the same pictures each run.
- **Claude tries what the change is about.** With your key set, Claude runs on the Mac. It reads what the change should do, taps through the app, looks at each screen, and decides what to try next. It writes a short report: what it tried, what it saw, and *works*, *broken* or *could not check*, with a reason.
- **`/verify` shows you the result here.** For a change to the phone app, `/verify` starts the check, waits for it, downloads the report, the screenshots and a short video, and shows them in the chat. The report also goes on the pull request.
  ```text
  iPhone check: works
  Tried: hold to talk, let go after 2 s
  Saw: the new voice note in the timeline
  Pictures: timeline, new-note, settings, voice
  Video: run.mp4
  ```

**What changes in how you work**

- **Nothing, unless you ask.** The check runs only when `/verify` starts it, or when you put the label *check on iPhone* on a pull request. A normal push doesn't run it, so small changes don't spend your key.

**What stays safe**

- **Your key is used only on your own branches.** GitHub never gives a key to a pull request from someone else's copy of the repository, and the label start works only for your own branches. A stranger can't spend your key.
- **Claude on the Mac can only use the simulator and its own folder of results.** It can't push code, change the repository, or read other keys.

**What is left out, and why**

- **Health data.** The simulator has almost no health data. Your last health check stays on your own iPhone, through TestFlight.
- **A screen you can tap live.** You get pictures and a video, not a live iPhone. A Mac you can use live costs money, so it stays for later.
- **Windows.** Relay Everything has no Windows app. The check is made so that a Windows job can be added later: the same brief for Claude, the same report and the same `/verify` step, with a Windows machine instead of a Mac.

**What you do yourself**

- **Give an Anthropic key once**, through a private link. It goes into the repository's secret store on GitHub, never into a file.

## What the build needs

- **Apple keys for TestFlight**: Ready. They are in the repository's secrets. The simulator check doesn't need them, because a simulator build is not signed.
- **Anthropic key for Claude on the Mac**: Needs you. Make a key in the Anthropic console. The build then sends a private link to save it as `ANTHROPIC_API_KEY` and copies it into the repository's GitHub secrets. Until then, the check runs the fixed tour only and says that Claude was skipped. Get it: <https://console.anthropic.com/settings/keys>

## Decision log

- **2026-11-06** — Asked how to check the iPhone app from a Linux computer → chose a Mac from GitHub, started on request, over a rented Mac or Docker-OSX (Apple's license allows macOS only on Apple hardware).
- **2026-11-06** — Asked whether Claude can run inside the GitHub job → chose yes: Claude Code runs on the Mac, explores the app and writes the report.
- **2026-11-06** — Asked about Windows → chose: no Windows check now, because there is no Windows app; make the check easy to copy for a Windows machine later.
- **2026-11-06** — Assumed: the Anthropic API key, not a Claude subscription token, because Matthew said "our Anthropic key". The check reads `CLAUDE_CODE_OAUTH_TOKEN` too, so a switch later needs no code.
- **2026-11-06** — Assumed: starts only from `/verify` or the *check on iPhone* label, never on each push, so a run spends the key only when asked.
- **2026-11-06** — Assumed: a fixed screen tour with no AI runs first and always, because the same pictures each run cost nothing and catch a broken build before Claude starts ([why](../../../wiki/agent-knowledge-center.md#most-process-improvements-shouldnt-use-ai)).
- **2026-11-06** — Assumed: Sonnet 5.5 for the Mac run, with at most 40 turns, to keep each run cheap; a run can ask for Opus 5.5.
- **2026-11-06** — Assumed: `/verify` learns the check from a project rule for `mobile/`, not an edit to the WongStack `/verify` skill, so a WongStack update keeps it.
- **2026-11-06** — Assumed: no website page changes, because the check is a tool for building the app and changes nothing a person sees in the app, server or ring. `mobile/README.md` and the wiki say how to use it.
- **2026-11-06** — Check: `.github/workflows/mobile-device-check.yml` is a new workflow that runs only on request. It loosens no check and gates nothing, like `/verify`.
- **2026-11-06** — Assumed: GitHub starts a workflow by hand only once it is on the default branch, so before the merge `scripts/device-check.mjs` falls back to the *check on iPhone* label when given `--pr`. Both starts stay.
- **2026-11-06** — Assumed: no `synchronize` start for a labelled pull request, because the spec says a push never starts the check. To run it again, take the label off and put it on again.
- **2026-11-06** — Assumed: Claude writes `out/claude/report.md` and `out/claude/verdict.txt`. The job's last step writes the final `out/report.md` and `out/verdict.txt` from the build, the tour and Claude, and a failed tour step makes the verdict *broken* whatever Claude says.
- **2026-11-06** — Assumed: Claude gets the job's read-only `github_token`, so the action never asks the Claude GitHub app for a write token, which also fails for a workflow not yet on the default branch.
- **2026-11-06** — Assumed: Maestro 2.12.1 from its release zip, checked by SHA-256; every action pinned by commit, at the major versions the other workflows use.
- **2026-11-06** — Assumed: no semantics label added in `lib/`: the tour taps visible text and the Settings button's tooltip, which Flutter gives as its label.
- **2026-11-06** — Assumed: the review's two findings are fixed in the workflow: Claude's commands never see the key, and Claude writes only in its results folder, because the spec already promises both.
- **2026-11-06** — Checkpoint: source, tests and docs built and reviewed; local checks pass. The live runs on GitHub's Mac (2.1–2.3, 3.2, 3.3, 4.1) and the key (1.1, 1.2) are still open.
- **2026-11-06** — First live run (label start, no key): the app built for the simulator, installed and opened on an iPhone 17 (iOS 26.5); whisper.cpp and the health plugin needed no change. Two tour flows failed only because Flutter joins a row's lines into one label; the flows now match the start of the text. The report comment reached PR #20.

## Capabilities

### New Capabilities

- `relay-app-device-check`: an on-request check of the phone app on a simulator in GitHub Actions: how it starts, the fixed tour, the Claude run and its limits, the report and pictures, and how `/verify` gets them.

### Modified Capabilities

None.

## Impact

- New workflow `.github/workflows/mobile-device-check.yml` (macOS runner, `workflow_dispatch` and `pull_request` `labeled`).
- New `mobile/device-check/`: Maestro flows for the fixed tour, and `brief.md`, the platform-neutral brief for Claude.
- New `scripts/device-check.mjs` and its test: start, wait and download from this computer.
- New rule `.agents/rules/mobile.md` (paths `mobile/**`): `/verify` runs the device check for a phone app change.
- `.env.example`: blank `ANTHROPIC_API_KEY=`; GitHub secret `ANTHROPIC_API_KEY`.
- Docs: `mobile/README.md` (*Builds on GitHub*), a new `wiki/development/device-check.md`, linked from `wiki/development/README.md` and `wiki/development/staging-walkthrough.md`.
- New dependencies in CI only: `anthropics/claude-code-action`, Maestro.
