# Take the ring out of everything people read

**Status:** ready-to-ship
**Branch:** curvy-platypus
**Open questions:** none

## Why

The Relay Everything ring is gone, but the website still has a whole *The ring* section, and the phone app, the web page and the AI connector still talk about ring notes. A reader thinks a ring is coming. This change takes the ring out of every place a person reads it, and keeps the notes the ring sent.

## What Changes

- **The website has no ring.** The *The ring* section and its four pages (*How it works*, *Parts and battery*, *The board*, *Models*) go, with their pictures. An old ring page address opens the home page, so a saved link or a search result still lands somewhere. The home page, *What you need* and *Privacy* lose their ring text, and so do the pages on notes, voice notes, photos, settings, Claude Code and the API.
  ```text
  Docs menu, before              Docs menu, after
  -----------------              ----------------
  Get started                    Get started
  Use the app                    Use the app
  Connections                    Connections
  Server API                     Server API
  Web API                        Web API
  The ring                       About
    How it works                   Privacy
    Parts and battery
    The board
    Models
  About
    Privacy

  relayeverything.com/ring/board/  →  relayeverything.com/
  ```
- **Old ring notes stay, as plain notes.** Nothing is deleted from anyone's space. A note the ring sent keeps its words, place and recording. Where a page must name these notes, it calls them *older recorded notes*. A program that reads notes or gets webhooks gets them the same as today.
  | Where | Before | After |
  |---|---|---|
  | Privacy | Ring notes: the words and the recording … The Relay Everything ring will send through the phone app when it is ready. | Older recorded notes: the words and the recording … No longer sent. The older recorded notes already in your space stay. |
  | Recordings (API) | The route that plays a ring note's recording. | The route that plays an older recorded note's recording. |
  | Your notes | Where a ring note's place comes from | (section goes: the place rule is on *Location*) |
  | Photos | Your ring recordings, notes, health and places stay. | Your recordings, notes, health and places stay. |
- **The phone app's words.** The Account page and the iPhone's location question name no ring. Phones get the new words with the next app build.
  | Where | Before | After |
  |---|---|---|
  | Account, *Open your Relay Everything page* | Your ring notes, recordings and the notes from all your devices. | The notes from all your devices, with their recordings. |
  | iPhone asks for location *Always* | … also while the app is closed, so ring notes get a place. | … also while the app is closed, to make your stays and trips. |
- **The web page's words.** Notes show no *Ring* or *Typed* label. An empty list says *No notes yet. Write one in the Relay Everything app.* The photo delete box and the app's short description name no ring. If the new web page (the *web page becomes the phone app* plan) goes live first, these screens are gone and this part is skipped.
  ```screen
  <div class="card col gap">
    <div class="row gap"><span class="tag">Ring</span><span class="muted">Wed 4 Nov, 11:15 · King St W</span></div>
    <p>Lunch idea: try the new café on Queen.</p>
  </div>
  <div class="sep"></div>
  <div class="card col gap">
    <div class="row gap"><span class="muted">Wed 4 Nov, 11:15 · King St W</span></div>
    <p>Lunch idea: try the new café on Queen.</p>
  </div>
  ```
  No real picture: only a label and words change, so the top card is today and the bottom card is after.
- **The AI connector's words.** The connector tells your AI it holds *one person's notes from their phone*, not *from a smart ring and their phone*. A note with no words is titled *A recorded note with no words*.
- **The hold-to-talk circle.** The docs call the amber shape that fills round *New note* a *circle*, not a *ring*, so no reader takes it for the device.
- **A check keeps the ring out.** The project's checks fail when the word *ring* shows in text people read: the website, the phone app, the web page, the AI connector, the plugin and every README. Hidden names pass: the note value `ring`, the `relay-ring` folder and the `/relay:` commands.
  ```text
  start/what-you-need.md:13
  | **The Relay Everything ring** …
  ✗ "ring" in text people read
  ```
- **The plugin and the README need nothing.** Neither names the ring today; the new check keeps it so.

## What the build needs

- **Nothing from you.** After it goes live, the assistant publishes the website and the server, as each publish does. The phone words reach phones with the next build, which goes to TestFlight by itself.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-website`: the home page and docs requirements drop the ring; the notes scenario says older recorded notes show as plain notes; a new requirement says no text people read names the ring, and old ring addresses open the home page.
- `relay-brand`: the logo scenario no longer excepts *the ring's own pages*.

## Impact

- `site/`: delete `src/content/docs/ring/` and `src/assets/ring/`; drop the ring entry in `sidebar.mjs`; add `public/_redirects` for `/ring/*`; edit `index.mdx`, `start/what-you-need.md`, `privacy.md`, `app/your-notes.md`, `app/voice-notes.md`, `app/photos.md`, `app/settings.md`, `connections/claude-code.md`, `connections/your-database.md`, `api/keys.md`, `api/recordings.md`; regenerate `api/v1-reference.md`, `public/api/v1.openapi.json` and `public/webhooks/v1.schema.json`.
- `app/worker/relay-mcp/`: `tools.ts` instructions, `inputs.ts` and `api.ts` descriptions, `answers.ts` empty title. `app/worker/apps/relay/webhooks/format.ts`: three descriptions.
- `app/src/apps/relay/`: `Notes.tsx`, `Photos.tsx`, `app.json`, and their tests (skipped if `flutter-web-app` removed them).
- `mobile/`: `lib/screens/account.dart`, `ios/Runner/Info.plist`, `README.md`, a stale comment in `lib/voice/transcriber.dart`.
- `scripts/product-name.test.mjs`: a second check over the same files.
- `wiki/relay-website.md`, `wiki/brand.md`, `wiki/open-source.md`, `AGENTS.md`: stale ring rules go.
- Unchanged: stored data, the `source` value `ring` in the API and webhooks, the audio route, the `relay-ring` folder, `/relay:` commands, archived plans.

## Decision log

- **2026-11-09** — Told in the request: do this in its own workspace, so it can go live before the web page change; hidden names stay (the `relay-ring` folder, `source: 'ring'`, `/relay:` commands); old ring notes stay in people's spaces and show as plain notes; whichever of this and `flutter-web-app` publishes second catches up.
- **2026-11-09** — Asked how this fits with the waiting home page plan (`landing-page-refresh`) → chose *Keep going here*: this plan removes the ring from the home page too, and whichever goes live second drops any ring text the other left.
- **2026-11-09** — Assumed: public text calls the ring's notes *older recorded notes*, and the API and webhooks keep the value `ring`, because a receiver that reads the value would break, and stored notes keep it.
- **2026-11-09** — Assumed: the recordings route, its API page and the `source` filter stay, reworded, because a person's older recordings still play through them.
- **2026-11-09** — Assumed: an old `/ring/` address opens the home page, because saved links and search results still point there.
- **2026-11-09** — Assumed: the docs call the hold-to-talk shape a *circle*, because *ring* reads as the device and the new check refuses it. The code names (`HoldRingPainter`) stay: no person reads them.
- **2026-11-09** — Assumed: a check refuses *ring* in text people read, reusing the product-name check's file list, because old pages and archived plans hold ring text that a later change can copy back.
- **2026-11-09** — Assumed: code comments that describe stored ring data stay, as they are still true; the transcriber comment that promises a ring goes.
- **2026-11-09** — Assumed: the wiki and `AGENTS.md` lose their ring rules (the ring circle, the ring pictures, *ring* in the website-page rule); the *JLC print orders* line stays, because it routes a chat, not product text.
- **2026-11-09** — Assumed: the *Pebble ring* in the device check stays, because it is the person's own Pebble device, not the Relay Everything ring, and no public page shows it.
- **2026-11-09** — Assumed: the home page's *A ring to take notes* heading becomes *Your own space*, because without a heading the sign-up and *built in the open* lines fall under *How your data travels*.
- **2026-11-09** — Check: `site/src/assets/ring/click-test.png` is deleted, which the loosened-checks step reads as a deleted test because of its name, because it is a picture of the ring's click test print on a deleted ring page, not a test.
- **2026-11-09** — Check: `site/src/assets/ring/wear-test.png` is deleted, which the loosened-checks step reads as a deleted test because of its name, because it is a picture of the ring's wear test print on a deleted ring page, not a test.
- **2026-11-09** — Saved for the staging check: tasks 1.1 to 7.1 built and passing locally; 7.2 (the staging preview) runs from this save.
- **2026-11-09** — Archived for publishing: staging showed no ring menu, `/ring/board/` opened the home page with a 301, and only the `source` value `ring` was left; main (#81, #83, #84) merged in and the ring check still passes.
