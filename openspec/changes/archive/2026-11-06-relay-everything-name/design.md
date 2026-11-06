# Design

## Context

See proposal.md, Why. The Cloudflare rename (`relay-everything-cloudflare-rename`) already changed every Cloudflare name. About 600 lines still say *Relay* outside `vendor/` and the OpenSpec archive. Most are code comments and identifiers. The rest are text a person reads: Flutter strings, `Info.plist` and `AndroidManifest.xml`, React strings on the server page, MCP sign-in HTML, plugin manifests and messages, Astro docs, READMEs and the wiki.

## Goals / Non-Goals

- Goal: one product name in every string a person reads, and a check that keeps it so.
- Non-goal: any identifier, route, table, file name, bundle ID, plugin name or Cloudflare name. Code comments stay.

## Decisions

- **Edit by hand, file by file, not by a global replace.** A global `s/Relay/Relay Everything/` also hits the Dart class `Relay`, `RelayController`, `RELAY_*` variables, `relay-only`, `relayApp`, `/apps/relay/` and phrases that already say *Relay Everything*. Each edit changes a string literal or prose only.
- **A name check, as a test.** `scripts/product-name.test.mjs`, added to the `node --test` list in `app/package.json`'s `test` script so CI runs it, reads the user-facing files: `site/src/content/**`, `site/astro.config.mjs`, `site/public/webhooks/*`, `mobile/lib/**` string literals, `mobile/ios/Runner/Info.plist`, `mobile/android/app/src/main/AndroidManifest.xml`, `app/src/apps/relay/*.tsx` (not tests), `app/worker/relay-mcp/{auth,index,tools}.ts`, `app/vite.config.ts`, plugin manifests, `plugin/hooks/hooks.json`, `plugin/lib/state.mjs` and `plugin/bin/*.mjs` strings, `scripts/relay-device-key.mjs`, `scripts/relay-mcp-trial.mjs`, every `README.md`, `self-host/SETUP.md` and `wiki/**`. It fails on `\bRelay\b(?! Everything)` with a file and line. To stay narrow, it checks Markdown and HTML text, and in code only quoted strings; identifiers and comments pass. Alternative weighed: a lint rule per language; rejected, because three languages need one rule and a test is simpler.
- **Allowed exceptions are explicit.** The check keeps a short list of allowed phrases, such as the `/relay:` commands, `relay-*` file and script names, `RELAY_*` variables, `apps/relay` paths and links into the OpenSpec archive. Each exception is a literal, not a broad pattern.
- **Generated files follow their source.** `site/src/content/docs/api/reference.md` comes from `npm run relay:api-doc`; `site/public/webhooks/v1.schema.json` comes from `app/worker/apps/relay/webhooks/format.ts` descriptions. Edit the source, then regenerate, so the drift checks stay green.
- **The iOS icon label** is `CFBundleDisplayName = Relay Everything`. iOS truncates it on the home screen; the person chose the full name.
- **The MCP server keeps `name: "relay"`** and takes `title: "Relay Everything"` and `resource_name: "Relay Everything"`; AI apps show the title.

## Risks / Trade-offs

- [Tests assert the old strings] → update each assertion with its string in the same edit; the full test run catches any miss.
- [Longer strings wrap on small phones] → check the timeline title and the Settings switch at 360 px wide in a widget test with a narrow surface; shorten the sentence, never the name.
- [The name check flags a word that is not the product, such as an electrical relay in `pcb/`] → `pcb/` netlists and KiCad files are out of the check; prose in `pcb/*.md` uses *relay* in lowercase only for the part.

## Migration Plan

No data moves. The phone app ships as a normal update under the same store ID. The server and connector publish as usual; the website republishes with `node scripts/publish-relay-site.mjs`. Rollback is a revert.
