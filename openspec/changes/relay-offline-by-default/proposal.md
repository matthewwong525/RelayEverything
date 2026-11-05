# Relay offline by default

## Why

Relay is the fastest way to take a note wherever you are, and a note is private until you choose to share it. Today's first version sends every note, and your health and location, to the Relay server from the start. Now the app keeps everything on your phone. Sending is an add-on that you turn on when you want to do more with your notes.

## What Changes

- **Relay works with no server.** You open the app and write a note at once. You need no key, no account and no signal. Notes stay on your phone, and the app sends nothing.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Relay</h3><span class="grow"/><span class="tag-outline">On this phone</span></div>
    <div class="card col"><span class="row gap"><span class="tag-outline">Typed</span><span class="muted">9:41 · Pinned</span></span><span>Call the PCB fab about the flex stiffener</span></div>
    <div class="card col"><span class="row gap"><span class="tag-outline">Typed</span><span class="muted">8:15</span></span><span>Order more TL3312 switches</span></div>
    <div class="row gap"><span class="grow"/><button class="btn-primary">New note</button></div>
  </div>
  ```
  The phone app is Flutter, which this site can't run, so its screens are sketches.
- **Sending is an add-on in Settings.** *Send to your Relay server* is off until you turn it on and connect this phone's key. Health and location history sit under it: they exist only to send, so they turn on only with it.
  ```screen
  <div class="card col gap phone">
    <h3>Settings</h3>
    <div class="row gap"><span class="grow">Pin notes to where I am</span><span class="tag-outline">Off</span></div>
    <div class="sep"/>
    <div class="row gap"><span class="grow">Send to your Relay server</span><span class="tag-outline">Off</span></div>
    <span class="muted">Your server can pass notes to your own database and your AI. Off: nothing leaves this phone.</span>
    <div class="row gap"><span class="grow muted">Health: steps, heart rate, sleep, workouts</span><span class="tag-outline">Off</span></div>
    <div class="row gap"><span class="grow muted">Location history</span><span class="tag-outline">Off</span></div>
  </div>
  ```
- **Turning sending on asks about your earlier notes.** You choose to send the notes you took offline, or only new ones. Nothing old leaves the phone by surprise.
  ```screen
  <div class="card col gap phone">
    <h3>Send your 42 earlier notes too?</h3>
    <span class="muted">They were only on this phone. New notes go to your Relay server from now on.</span>
    <div class="row gap"><span class="grow"/><button class="btn-ghost">Only new notes</button><button class="btn-primary">Send them</button></div>
  </div>
  ```
- **Turning sending off stops it.** Notes stay on your phone. The copy already on your server stays there. Health and location that did not go yet are dropped, and the app stops reading them.
  ```screen
  <div class="card col gap phone">
    <h3>Stop sending?</h3>
    <span class="muted">New notes stay on this phone. Notes already on your Relay server stay there. Health and location stop.</span>
    <div class="row gap"><span class="grow"/><button class="btn-ghost">Cancel</button><button class="btn-primary">Stop sending</button></div>
  </div>
  ```
- **Your own database and your AI read only what you send.** They get notes from your Relay server, so a note that stays on your phone never reaches them. Pebble ring notes come through Pebble's app to your server, so they need sending on.
  ```mermaid
  flowchart TD
    A["Note on your phone"] --> B{"Sending on?"}
    B -->|"no"| C["Stays on this phone"]
    B -->|"yes"| D["Your Relay server"]
    E["Pebble ring"] --> F["Pebble app"] --> D
    D --> G["Your own database"]
    D --> H["Your AI"]
  ```

Non-goals: end-to-end encryption, deleting the server copy from the phone, the phone sending straight to your own database, and ring notes from Pebble without sending on.

## What the build needs

- **Nothing else from you.** The build starts after the Relay app first version publishes; that chat, *Set up the Relay ring repo*, is building it now.
- **Your iPhone and Android phone**: Ready, you have them, for the final check.

## Capabilities

### New Capabilities
- `relay-sending`: the phone app keeps notes local by default and sends notes, health and location to a Relay server only while the person has turned sending on; the earlier-notes choice; what turning off keeps and drops.

### Modified Capabilities
- None. `relay-sync` and `relay-notes` are still in the unshipped `relay-app-first-version` change; their behavior with sending on stays as written there.

## Impact

- Changed: `mobile/` (settings model, outbox, health and location sync, connect flow, timeline header, tests), `mobile/README.md`, `app/src/apps/relay/` *Set up a phone* dialog text, `AGENTS.md`'s Relay section, and the public website's pages in `site/src/content/docs/` that describe syncing (`index.mdx`, `start/connect-a-phone.md`, `app/settings.md`, `app/your-notes.md`, `privacy.md`).
- No server route, table or migration changes.
- The public relay-app repository gets the new default on the next publish.

## Decision log

- **2026-11-05** — Settled by Matthew: "we should support fully offline notes as well!!! this is an add on if they want to do stuff and will likely use the same webhooks infrastructure" and "the default is offline".
- **2026-11-05** — Settled by Matthew, relayed by the Relay MCP chat: "health data will stay in the health app as well if not synced", so with sending off the app keeps no health copy and does not read health.
- **2026-11-05** — Asked where Pebble ring notes go with sending off → chose they stay in Pebble's app; Relay offline holds typed notes only until the Relay ring talks to the phone.
- **2026-11-05** — Asked what happens to earlier offline notes when sending turns on → chose ask at the switch: send them, or only new notes.
- **2026-11-05** — Asked what happens to the server copy when sending turns off → chose keep it, with no delete action.
- **2026-11-05** — Asked how end-to-end encryption fits → chose not now.
- **2026-11-05** — Assumed: webhooks and the AI keep reading from the Relay server, and the phone outbox records a destination so the webhooks change can add a phone-side kind, because the webhooks plan sends from the server today and Matthew's answer on phone-side sending is still open there.
- **2026-11-05** — Assumed: location history is collected only while sending is on, like health, because it exists to place ring notes on the server.
- **2026-11-05** — Assumed: *Pin notes to where I am* is its own switch, off by default, and works offline, because a typed note's pin needs no server.
- **2026-11-05** — Assumed: with sending off the app looks up no place names, and a pinned note shows *Pinned*, because the phone's place lookup asks Apple or Google over the network.
- **2026-11-05** — Assumed: the phone keeps its key after sending turns off, so turning it back on needs no new scan, because the key stays in the phone's secure storage either way.
- **2026-11-05** — Assumed: health starts from the day sending and health turn on, with no earlier backfill, because nothing was kept before and a backfill would be a second choice at the switch.
- **2026-11-05** — Assumed: *Disconnect this phone* stays, inside the sending section, and forgets the key and turns sending off, because the first version already has it and a person needs a way to remove a key.
- **2026-11-05** — Assumed: the plan no longer says the Relay ring will reach the phone directly later, because Matthew said on 2026-11-05 that Relay's focus is the app and the ring may never launch.
- **2026-11-05** — Assumed: the public website's pages that describe syncing change with the app, because the website went live after this plan was written and now says the app syncs to the server.
- **2026-11-05** — Assumed: this is a follow-up change on top of the first version, not folded into it, because that chat is already building and this part was asked to plan separately.
- **2026-11-05** — Assumed: a typed note on both the phone and the server shows once by its time and words, because the server's timeline gives no `clientId` and this change makes no route change.
- **2026-11-05** — Assumed: server notes stay in the first version's timeline cache, not in the `notes` table, because the cache already keeps them when sending turns off and only *Disconnect* clears it.
- **2026-11-05** — Assumed: tapping *Pinned* does not open the map app yet, because that needs a new package and no task asks for it.
- **2026-11-05** — Assumed: the setting keeps the first version's name `history`, not `locationHistory`, so the saved settings read back with no rename.
- **2026-11-05** — Assumed: health's first read starts when it turns on, less the first version's 2-hour overlap, because the overlap catches readings the health store saves late.
- **2026-11-05** — Assumed: a phone whose key is gone, such as after a restore, reads sending as off, because it can not send with no key.
- **2026-11-05** — Assumed: the check that the first version's tests pass ran on a clean copy of `main` after the source was written (38 tests, not 34), because the build writes all source before it runs any test.
