# Tasks

## 1. Remove the ring hardware

- [x] 1.1 Delete `pcb/`, `vendor/` and `cad/`.
- [x] 1.2 Delete `site/scripts/render-ring.sh` and the `render-ring` script in `site/package.json`; keep the ring pictures in `site/src/assets/ring/`.
- [x] 1.3 Remove the *on GitHub* links from `site/src/content/docs/ring/board.md` and `ring/models.md`, keeping each page's words true.
- [x] 1.4 Remove the STL and `__pycache__/` lines from `.gitignore`.

## 2. Move the self-host tool into the app

- [x] 2.1 `git mv self-host app/self-host`; fix the paths in `setup.mjs`, `setup.test.mjs`, `bindings.test.mjs` and the three templates (comments included).
- [x] 2.2 In `setup.mjs`, move an old install's ignored files from `<repo>/self-host/` on first run, by design.md; add its tests to `setup.test.mjs`.
- [x] 2.3 Update the callers: `app/package.json`'s test line, `app/vite.config.ts`, `app/src/relay-only.tsx`, `app/worker/relay-only.ts`, `.gitignore`, `scripts/product-name.test.mjs`.
- [x] 2.4 Update `site/src/content/docs/start/run-your-own.md` and `app/self-host/SETUP.md` to name `app/self-host/`.

## 3. Docs

- [x] 3.1 Rewrite `README.md` by design.md.
- [x] 3.2 Update `AGENTS.md`: the project paragraph names `app/`, `mobile/`, `site/` and `plugin/`; drop the STL rule.
- [x] 3.3 Update `wiki/open-source.md` (what is public, the self-host paths) and `wiki/relay-website.md` (drop the ring render line).
- [x] 3.4 Search the repository, outside `openspec/changes/archive/`, for `pcb/`, `cad/`, `vendor/` and `self-host/`; fix each live reference.

## 4. Checks

- [x] 4.1 Run the app checks (`cd app && npm test`), the website checks (`cd site && npm test`), `node --test scripts/*.test.mjs` and `node scripts/public-check.mjs`; fix what fails by design.md.
- [x] 4.2 Run `node app/self-host/setup.mjs check` with no key and confirm it fails cleanly, naming `app/self-host/.env`.
- [ ] 4.3 `/save`, then confirm CI passes and the staging website shows the *Run your own server* page with the new path.
