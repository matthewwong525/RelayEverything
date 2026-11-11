# Take a note with Siri in one sentence

**Status:** ready-to-ship
**Branch:** voice-assistant-note-taking
**Open questions:** none

## Why

You want to keep a note by speaking, in one sentence, hands free. Today Siri can start the iPhone app's *Add a note*, but it never asks for the words, so a spoken note fails. And *Relay Everything* is a long name to say to Siri each time.

## What Changes

- **Say the note in one sentence.** On an iPhone with the new Siri (iOS 27 with Apple Intelligence), say *Hey Siri, take a note in Relay, buy milk on the way home*. Siri asks nothing, says *Saved*, and the note is kept on the phone and sent as any typed note is. No real picture: Siri's talk shows on the phone's own screen, which the plan's prototype can't run.
  ```mermaid
  sequenceDiagram
    participant You
    participant Siri
    participant App as The app
    You->>Siri: Take a note in Relay, buy milk
    Siri->>App: Add a note: buy milk
    App-->>Siri: Kept
    Siri->>You: Saved
  ```
- **Other iPhones ask once.** Apple's older Siri can't take free words inside an app's phrase. There, *Hey Siri, take a note in Relay* makes Siri ask *What's the note?*, and your answer is kept. Today that same phrase fails.
  ```mermaid
  sequenceDiagram
    participant You
    participant Siri
    You->>Siri: Take a note in Relay
    Siri->>You: What's the note?
    You->>Siri: Buy milk
    Siri->>You: Saved
  ```
- **Siri knows the app as *Relay*.** *Add a note to Relay*, *Take a note in Relay* and *Note in Relay* all work, and the long name still works. The app's name on your Home Screen, in the App Store and on the website stays *Relay Everything*.
- **The website's Shortcuts page names what to say to Siri**, in one sentence and with the short name.

Non-goals: no Alexa or Google; no rename of the product; no Apple's old Siri note feature (SiriKit), which Apple marked as old in iOS 27.

## What the build needs

- **An iPhone with the new Siri, to try the one-sentence note**: Needs you. The iPhone check on this computer has no microphone and no Siri, so only your own iPhone, through TestFlight, can show it.
  ```form
  text: Does your iPhone have iOS 27 with Apple Intelligence on?
  ```

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-shortcuts`: *Add a note* asks for its words when the person can answer; Siri takes a note in one sentence where it can; Siri knows the app as *Relay*.

## Impact

- `mobile/ios/Runner/RelayIntents.swift`: `AddNoteIntent`'s `text` parameter gets a clear title, description and `requestValueDialog`; `perform` asks for `text` when it has no words and no files; the result speaks *Saved*; `RelayShortcuts` gains phrases.
- `mobile/ios/Runner/Info.plist`: the app-name synonym *Relay* for Siri.
- `scripts/product-name.test.mjs`: the synonym's plist entry and the website's spoken phrases go on its `ALLOWED` list.
- Docs: `site/src/content/docs/app/shortcuts.md`.

## Decision log

- **2026-11-10** — Asked what to do for Google, since Google Home speakers take no outside voice apps since 2023 → first chose to try Android's Gemini app functions; then, after the plan, chose no Google and no Alexa: Siri only.
- **2026-11-10** — Asked who can use an Alexa skill → chose test mode on one account; later dropped with Alexa.
- **2026-11-10** — Asked, after the plan, that Siri take the note in one go, not ask. Asked how → chose the new Siri in one sentence, with the question as the fallback on other iPhones; not Apple's old SiriKit note feature.
- **2026-11-10** — Asked, after the person said *Relay Everything* is a mouthful, what *just Relay* means → chose Siri answers to *Relay*; the product keeps the name Relay Everything.
- **2026-11-10** — Assumed: one-sentence notes rely on the new Siri reading the action's title and its words' description, with no Apple schema, because Apple has no notes schema we found; only a real iPhone can confirm it.
- **2026-11-10** — Assumed: *Saved* is Siri's reply, because a short reply suits speech.
- **2026-11-10** — Assumed, at ship: the iPhone check runs in the publish step's check, and the person's own try of *Hey Siri, take a note in Relay, buy milk* comes after TestFlight, so neither is a build task that would hold the publish.
- **2026-11-10** — Assumed, at build: the iOS build is left to CI, the gate, because this Linux computer can't build iOS; the Swift compiles first there.
- **2026-11-10** — Archive checkpoint: built, reviewed (a YAML quote and a Siri cancel fixed), archived for publish.
- **Check:** `scripts/product-name.test.mjs` gets its first `ALLOWED` literals: the Siri synonym and the spoken phrases, because Siri must hear the short name and the website must say it; every other bare *Relay* stays refused.
