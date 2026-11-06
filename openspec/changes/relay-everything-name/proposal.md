# Call the product Relay Everything everywhere people see it

**Status:** in-progress
**Branch:** rename-to-relay-everything
**Open questions:** none

## Why

The product is now Relay Everything: the website is relayeverything.com, the code lives in RelayEverything, and the Cloudflare parts already carry the new name. But the phone app, the website, your server's page and the docs still say just *Relay*. People see two names for one product.

## What Changes

- **The phone app says Relay Everything.** The name under the icon, the top of the timeline, Settings, the connect screen, and every message and permission prompt use the new name. The app keeps its store ID, so it updates in place and keeps your notes and key. An iPhone can cut the icon label to *Relay Everyt…*.
  ```screen
  <div class="row gap">
    <div class="card col gap phone">
      <p class="muted">Before</p>
      <div class="row gap"><h3>Relay</h3><span class="grow"/><span class="tag-outline">Settings</span></div>
      <div class="card col gap"><p>Ring notes and recordings are on your Relay page.</p><button class="btn-ghost">Open your Relay page</button></div>
      <p class="muted">Send to your Relay server</p>
    </div>
    <div class="card col gap phone">
      <p class="muted">After</p>
      <div class="row gap"><h3>Relay Everything</h3><span class="grow"/><span class="tag-outline">Settings</span></div>
      <div class="card col gap"><p>Ring notes and recordings are on your Relay Everything page.</p><button class="btn-ghost">Open your Relay Everything page</button></div>
      <p class="muted">Send to Relay Everything</p>
    </div>
  </div>
  ```
  Only the words change, so a sketch shows the result; the phone app has no prototype that runs here.
- **The website says Relay Everything.** relayeverything.com shows the new name in its title, its home page and every docs page, the webhook guide and the example receiver included.
  | Where | Before | After |
  |---|---|---|
  | Browser tab and header | Relay | Relay Everything |
  | Home page | Relay gets your notes… | Relay Everything gets your notes… |
  | Docs | your Relay server | your Relay Everything server |
- **Your server's page and the AI connector say Relay Everything.** The page heading, its messages and dialogs, the page title in the browser, and the *Connect Claude to Relay Everything?* screen use the new name. Claude and ChatGPT show the connector as Relay Everything.
- **The Claude Code plugin says Relay Everything.** Its description, its setup field and its messages use the new name. You still type `/relay:saving`: the command keeps its short name, so nothing you set up stops working.
- **The ring is the Relay Everything ring.** The ring docs, the 3D models' notes and the board notes use the new name.
- **The repository's guides and the wiki say Relay Everything**: the main README, the folder READMEs, the self-host guide and the wiki pages.
- **Hidden names stay the same.** Page addresses such as `/apps/relay/`, database tables, code names, file names, the `/relay:` commands and the app's store ID keep *relay*. Changing them would break links and saved data, and nobody sees them in use.

Non-goals: new pictures or a logo, the App Store listing (already *RelayEverything*), renaming code, folders, routes, tables, store IDs or Cloudflare parts, and changing what the product does.

## What the build needs

- **Nothing.**

## Capabilities

### New Capabilities
- `relay-everything-name`: the product shows the name *Relay Everything* wherever a person reads it (phone app, website, server page, AI connector, Claude Code plugin, docs), while identifiers, routes, tables and store IDs keep `relay`.

### Modified Capabilities

## Impact

- Phone app: `mobile/android/app/src/main/AndroidManifest.xml` (`android:label`), `mobile/ios/Runner/Info.plist` (`CFBundleDisplayName`, `CFBundleName`, usage strings), `mobile/lib/app.dart`, `mobile/lib/controller.dart`, `mobile/lib/screens/*.dart`, `mobile/lib/sync/location.dart`, `mobile/test/*`, `mobile/README.md`. `applicationId`/bundle ID `com.matthewwong525.relayApp` and the Dart class `Relay` stay.
- Server page and connector: `app/src/apps/relay/*.tsx`, `app/src/apps/relay/app.json`, `app/vite.config.ts` (`<title>`), `app/worker/relay-mcp/auth.ts`, `app/worker/relay-mcp/tools.ts` and `index.ts` (display `title`, `resource_name`, `instructions`; MCP `name: "relay"` stays), refusal messages in `app/worker/apps/relay/*.ts`, route descriptions, `app/worker/apps/relay/webhooks/format.ts` schema descriptions; tests beside each.
- Generated: `npm run relay:api-doc` in `app/` regenerates `site/src/content/docs/api/reference.md`; `site/public/webhooks/v1.schema.json` follows `format.ts`.
- Website: `site/astro.config.mjs`, `site/src/content/docs/**`, `site/public/webhooks/receiver.mjs`, `site/tests/*`.
- Plugin: `plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (descriptions and titles; `name: "relay"` stays), `plugin/bin/*.mjs`, `plugin/skills/*/SKILL.md`, `plugin/README.md`, `plugin/test/*`.
- Ring and docs: `cad/README.md`, `cad/*.scad` header comments, `pcb/PLAN.md`, `pcb/SCHEMATIC.md`, `README.md`, `AGENTS.md`, `self-host/SETUP.md`, `self-host/setup.mjs` messages, user-facing messages in `scripts/relay-device-key.mjs` and `scripts/relay-mcp-*.mjs`, `wiki/**`.
- Unchanged: `openspec/changes/archive/**` and `openspec/specs/**` text other than the new capability, `vendor/`, code comments, identifiers, routes, tables, file names, KiCad netlists, Cloudflare names.
- Depends on: `relay-everything-cloudflare-rename` (shipped).

## Decision log

- **2026-11-06** — Asked what changes from *Relay* to *Relay Everything* → chose the words people see; code names, page addresses, database tables and the store ID stay.
- **2026-11-06** — Asked what name goes under the phone's app icon → chose *Relay Everything*, even though an iPhone can cut it short.
- **2026-11-06** — Assumed: code comments keep *Relay*, because nobody using the product reads them and a rename of hundreds of comments makes the change hard to check.
- **2026-11-06** — Assumed: the Claude Code plugin and marketplace keep `name: "relay"`, and the MCP server keeps `name: "relay"`, because those are identifiers: a new plugin name changes the `/relay:` commands and makes people install again.
- **2026-11-06** — Assumed: the ring is *the Relay Everything ring*, because the ring is a device of the product, and the name must not depend on a ring.
- **2026-11-06** — Assumed: shipped specs and archived changes keep their text, because they record what shipped; one new capability holds the naming rule.
- **2026-11-06** — Assumed: on second mention in a long docs page, the text still says *Relay Everything*, not *Relay*, because one name for one thing follows the Simplified Technical English rule.
- **2026-11-06** — Assumed: a deterministic check enforces the name, a test that fails on a bare *Relay* in the files people read, because a later change otherwise brings the old name back.
- **2026-11-06** — Check: `app/package.json` adds `../scripts/product-name.test.mjs` to the `node --test` list in `test`, because CI runs that list; no check is loosened.
- **2026-11-06** — Assumed: the Settings switch says *Send to Relay Everything*, not *Send to your Relay Everything server*, because the longer title wraps at 360 px and the design says to shorten the sentence, never the name.
- **2026-11-06** — Checkpoint: tasks 1.1–6.1 built and reviewed (two review findings fixed: the 360 px wrap test and the name check's file list); local checks pass; saved for the preview check in 6.2.
