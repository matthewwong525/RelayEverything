# Tasks

## 1. Ring files

- [x] 1.1 Copy `cad/`, `pcb/` (no `__pycache__`) and `vendor/nordic-lib-kicad/` (no `.git`) from `/root/Relay`; add `vendor/README.md` with source and commit 05a4dae
- [x] 1.2 Add `*.stl` and `__pycache__/` to `.gitignore`
- [x] 1.3 Start `mobile/` with a short public README and a Flutter `.gitignore`

## 2. Publish script

- [x] 2.1 Write `scripts/publish-relay-app.mjs`: export, guard, clone, replace, commit, push, create when missing
- [x] 2.2 Write its test for the guard and the unchanged case
- [x] 2.3 Add the project rule to `AGENTS.md`, above the WongStack block

## 3. Cloudflare

- [x] 3.1 Run setup's `provision --route artifacts` for `relay-ring` and record what it made

## 4. Verification

- [x] 4.1 Run the local checks and the script's dry run
- [x] 4.2 `/save` the install and read its check run and preview (none until the first publish deploys main)
