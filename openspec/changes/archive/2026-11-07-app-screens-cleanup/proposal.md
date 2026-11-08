# Make the phone app feel like Apple Notes, in the Relay Everything brand

**Status:** ready-to-ship
**Branch:** cheerful-pelican
**Open questions:** none

## Why

The app now wears the Relay Everything colors, but each screen still has its old layout: a bare first screen, two floating buttons over the notes, and Settings as one long grey list with lines. This change gives the app the calm, familiar shape of Apple Notes, with one button to write or talk and a way to find a note, while each screen follows the brand's four rules.

## What Changes

- **A notes list like Apple Notes.** A large *Notes* title with the count and the sync state under it. Notes in groups by day: *Today*, *Yesterday*, *Previous 7 days*, *Previous 30 days*, then by month. Each group is one card with a row per note: the first line in bold, then the time and the rest of the words, then a small *Voice* or *Typed* tag, the length, the place and *Sent* or *Waiting to send*. A note with a picture shows it small at the right. Tap through every screen, light and dark, below.
  ```live
  folder: prototypes/app
  height: 940
  ```
  ```picture
  Before: pictures/before-timeline.webp
  ```
  The *Before* is today's screen from the last iPhone check. The *After* is the drawing above, because the phone app does not run in the plan's preview.
- **One *New note* button: tap to write, hold to talk.** *Search* and a round green *New note* button sit at the bottom, as in Apple Notes. *Hold to talk* goes away. Tap *New note* to open a plain page and type. Hold it: after half a second the phone buzzes and the button turns into an amber mic. Let go and the phone keeps listening. Tap anywhere to save the voice note, or tap *Cancel*. A voice note from Shortcuts or the Action button opens the same card, so you stop it the same way.
  ```mermaid
  flowchart TD
    A["Press New note"] -->|"under 0.5 s"| B["New note page"]
    A -->|"hold 0.5 s"| C["Mic: listening"]
    C -->|"let go"| C
    C -->|"tap anywhere"| D["Voice note saved"]
    C -->|"Cancel"| E["Nothing kept"]
  ```
- **Search your notes.** Type in *Search* and the list shows only the notes with those words, in their words, their place or their file names. It searches this phone only and works with no signal. *Cancel* shows the whole list again.
- **A ⋯ menu, and a page to read a note.** The ⋯ button at the top right holds *Settings*, *Sync now* and *Open your Relay Everything page*. The gear and the card at the top of the list move into it. Tap a note to read all of it on its own page: the words, pictures, files, and *Play* for a voice note. You read a note there; you can not edit it.
  ```screen
  <div class="row gap">
    <div class="card col gap"><span>Settings</span><div class="sep"></div><span>Sync now</span><div class="sep"></div><span>Open your Relay Everything page</span></div>
    <div class="card col gap"><span class="muted">Yesterday at 18:05 · Home</span><h3>Paint colours for the hall</h3><span>the warm grey, not the blue.</span><span class="tag-outline">swatches.pdf</span></div>
  </div>
  ```
- **Settings in three groups.** *Notes*, *Voice notes* and *Sending*, each a card with no lines inside, under a large *Settings* title. Each row has a short help line. With sending off, *Health*, *Calendar* and *Location history* are dim, and one line under them says they work with *Send my notes* on. Every switch stays, and each one works as it does today. The long details stay on the website's pages.
  ```picture
  Before: pictures/before-settings.webp
  ```
- **The sync state says its name, with a small live dot.** Under the title: a still green dot beside *Synced*, a small amber dot that pulses while it says *Syncing*, a hollow dot beside *2 waiting* or *Offline*, and a red dot beside *Key refused*. With sending off it says *On this phone*. If the phone is set to reduce motion, the dot stays still. The logo never moves.
  ```screen
  <div class="col gap">
    <h3>Notes</h3>
    <div class="row gap"><span class="muted">5 notes ·</span><span class="tag">● Synced</span><span class="tag">● Syncing (pulses)</span><span class="tag-outline">○ 2 waiting</span></div>
  </div>
  ```
- **The other screens match.** The *New note* page is plain, like Apple Notes: the first line shows bold, *Save* is the one green button, and the paperclip adds photos and files. The screen that asks where to send, and the dialogs, get the same corners, spacing and quiet buttons. The *Voice* and *Typed* tags stay; there is no new note type.
  ```picture
  Before, new note: pictures/before-new-note.webp
  ```
- **The iPhone share sheet wears the brand.** When you share into Relay Everything from another app on an iPhone, the sheet shows the paper color, a card for what you share, the green *Save* and the Inter font, in light and dark, like the Android share card. It still works with no network.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">Cancel</button><span class="grow"></span><h3>Relay Everything</h3><span class="grow"></span><button class="btn-primary">Save</button></div>
    <div class="card col gap"><span>Hiking trails near Lynn Canyon</span><span class="muted">https://example.com/trails/lynn-canyon</span></div>
    <div class="field">Add words</div>
    <span class="muted">Sending is on: this goes to your space.</span>
  </div>
  ```
- **The website's app pages say the same.** The *Your notes*, *Voice notes*, *Shortcuts*, *Settings* and *Share* pages describe the list, search, the ⋯ menu, holding *New note* to talk, and the three Settings groups.

Non-goals: editing a note after you save it; pinned notes or folders; a new note type; a change to what any switch does or sends; a moving logo; the Relay Everything page on your server.

## What the build needs

- **Nothing.** The font, the colors and the App Store Connect key for the TestFlight build are ready from the brand change.

## Capabilities

### New Capabilities

- `relay-notes-screen`: the phone's notes list grouped by day, search on the phone, the ⋯ menu, the read-only note page, and the one *New note* button that writes on a tap and records on a hold.

### Modified Capabilities

- `relay-voice-notes`: a voice note starts by holding *New note* for half a second, keeps recording after the finger lifts, and saves on a tap anywhere; a shorter press opens the *New note* page.
- `relay-shortcuts`: *Start a voice note* opens the same listening card, which saves on a tap anywhere.
- `relay-brand`: the iPhone share sheet wears the brand; each app screen follows the four screen rules; the sync state says its name beside a dot that moves only while syncing.

## Impact

- `mobile/lib/brand.dart`: the body size moves to 16; list tile, card, dialog and large-title styles; the sync dot.
- `mobile/lib/screens/timeline.dart`: rebuilt as a large-title list with day groups, rows, search, the ⋯ menu and the bottom dock; a new `screens/note.dart` for the read-only note page.
- `mobile/lib/screens/hold_to_talk.dart`: the hold gesture moves onto *New note* with a 0.5 s threshold and a lock; the listening card replaces the *Hold to talk* button and the recording sheet.
- `mobile/lib/screens/settings.dart`, `compose.dart`, `connect.dart`; `mobile/lib/share/share_card.dart` for the body size only.
- `mobile/ios/ShareExtension/`: brand colors, Inter in the extension with its license, `UIAppFonts` in its `Info.plist`, and the font in the extension target.
- `mobile/test/`: screen, voice and offline tests for the new gestures, search, groups, menu and note page; a check that the iPhone share sheet's colors equal `BrandColors`.
- `mobile/device-check/flows/`: the flows that wait for or tap *New note* and *Hold to talk*.
- `mobile/README.md`, `wiki/brand.md`, and the website's app pages.
- No server, data, route or key change.

## Decision log

- **2026-11-07** — Asked whether the iPhone share sheet gets the brand → chose *Colors and Inter*, like the Android share card; the sheet carries its own copy of the font.
- **2026-11-07** — Asked how far the Settings cleanup goes → chose *Group into cards*: *Notes*, *Voice notes* and *Sending*, no lines, shorter help text, every switch unchanged.
- **2026-11-07** — Asked whether anything moves while the phone sends → chose *Pulse on the sync chip*: an amber dot pulses only while *Syncing*; the logo stays still.
- **2026-11-07** — Asked, in chat, whether the two floating buttons are needed → chose a Messages-style bar at first, then, asked again, chose an Apple Notes layout: *Search* beside one *New note* button that writes on a tap and records on a hold, a ⋯ menu at the top right, and more Apple Notes looks.
- **2026-11-07** — Asked, in chat, how holding *New note* records → after a hold it becomes a mic, the person can let go, and a tap anywhere on the screen ends the recording.
- **2026-11-07** — Assumed: the hold turns into a mic at 0.5 s, with a small buzz, because the phone's own long press is about that long and the voice notes rule already treats a press under 0.5 s as no recording.
- **2026-11-07** — Assumed: a tap anywhere saves the voice note and only *Cancel* throws it away, because slide-off-to-cancel needs a held finger, which the person no longer keeps down.
- **2026-11-07** — Assumed: the Shortcuts and Action button recording uses the same listening card, because two ways to stop one recording would confuse.
- **2026-11-07** — Assumed: the large title says *Notes* and the Signal R sits at the top left, because Apple Notes titles the list by what it holds and the mark keeps the brand on the screen.
- **2026-11-07** — Assumed: tapping a row opens a page to read the whole note, with no editing, because compact rows can not show every picture, file and *Play*, and editing a sent note would need a new way to send changes.
- **2026-11-07** — Assumed: no pinned notes or folders, because they are new features, not the cleanup asked for.
- **2026-11-07** — Assumed: *New note* stays filled green and *Search* has no mic, against Apple Notes, because the brand keeps one bright thing per screen and the iPhone keyboard has its own dictation.
- **2026-11-07** — Assumed: search reads the note's words, its place and its file names on the phone only, case-insensitive, because the app is offline by default.
- **2026-11-07** — Assumed: no new note type and no change to the *Voice* and *Typed* tags, because the person asked to be asked first before a new note type.
- **2026-11-07** — Assumed: the plan's *After* is a drawn HTML prototype, not the running app, because the phone app does not run in the plan's preview and Flutter is not on this computer; the iPhone check after the build shows the real screens.
- **2026-11-07** — Assumed: with sending off, the long help text under *Health*, *Calendar* and *Location history* becomes one short line each, plus one shared line, because the website's *Health*, *Calendar* and *Location* pages already hold the details.
- **2026-11-07** — Assumed: the dot stays still when the phone asks for less motion, because a pulse can bother some people and the words already say the state.
- **2026-11-07** — Asked, in chat, why the drawing showed blank → fixed the drawing: a name in its script clashed with the browser's own, so it stopped before it drew, and the day cards now keep their full height.
- **2026-11-07** — Assumed: the listening card shows whenever a recording runs, in the phone's top layer, so a hold on *New note* and a Shortcuts recording share one card and it stays over any page.
- **2026-11-07** — Assumed: the hold uses Flutter's own long press, which starts at 0.5 s, so the time matches the phone's other long presses.
- **2026-11-07** — Assumed: the line under the clock on the listening card stays still, because the recorder gives no sound level to draw.
- **2026-11-07** — Assumed: a voice note too short to keep says *Too short to keep. Nothing was saved.* for a hold and for Shortcuts alike.
- **2026-11-07** — Assumed: the share sheet asks iOS for Inter as `InterVariable` and `InterVariable-SemiBold`, the names in the font file; if iOS 15 does not find the semi-bold name, the title falls back to the system font.
- **2026-11-07** — Check: the slide-off-to-cancel test is replaced by the *Cancel* test, because the hold no longer ends on a lift; no other test was dropped.
- **2026-11-07** — Check: the Inter test in `brand_test.dart` lists `headlineMedium` and the list row styles in place of the app bar's title style, because the theme no longer sets that style; it still fails on any text style without Inter.
- **2026-11-07** — Built every screen, test and page; a second look found four problems, all fixed (the bold first line while a keyboard composes, a listening card that could stay stuck, a failed save offering a retry with no card, and the connect page's words). Saved for the iPhone check, task 8.2.
- **2026-11-07** — Asked how to finish after the iPhone check showed every new screen in light mode but did not reach dark mode or the iPhone share sheet (its Claude part gave no report; the fixed tour passed) → chose *Publish now*; dark mode and the share sheet were not seen on a device. TestFlight build 84 holds this code.
- **2026-11-07** — Archived for publishing; every task ticked.
