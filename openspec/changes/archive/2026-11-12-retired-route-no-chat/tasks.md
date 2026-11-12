# Tasks

## 1. WongStack

- [x] 1.1 In a WongStack branch (not the `~/.cache/wong-stack` clone), change `failed` in `.agents/skills/daily/scripts/worker.mjs`: a `reason` matching `/^\d{3}: retired\b/` writes `note()` at most once a day for that kind and returns without counting.
- [x] 1.2 Add a test to `scripts/tests/daily-worker.test.mjs`: two `retired` failures in a row write one journal line and open no chat; a later real failure still opens one after two in a row.
- [x] 1.3 Add the `daily-routine` spec delta (a retired answer opens no chat) and the `CHANGELOG.md` entry by WongStack's payload release rule.
- [x] 1.4 Open the WongStack pull request, with the case for why every repo needs it (outward).

## 2. This repo

- [x] 2.1 Copy the same `worker.mjs` edit into `.agents/skills/daily/scripts/worker.mjs`.

## 3. Checks

- [x] 3.1 Run WongStack's `daily-worker` tests and its payload checks; all pass.
- [x] 3.2 `/save` here and check CI passes.
