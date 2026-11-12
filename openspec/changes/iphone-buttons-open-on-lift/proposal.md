# Buttons on iPhone open when you lift your finger, even after a long press

**Status:** building
**Branch:** salty-fox
**Open questions:** none

## Why

On 2026-11-12 the iPhone check failed three times at its Settings step, on a slow test Mac. The check's tap on Home's gear lasted about 1 second, so the app took it as a long press. It showed a small *Settings* bubble and did not open Settings. This happened in 3 of 4 tries. The same check runs before each release, so it can also stop a release.

A real person can do the same: a slow press on a round button shows its name and does nothing. Other iPhone apps open a button when you lift your finger, however long you held it.

## What Changes

- **A slow press on a round button opens it, as on other iPhone apps.** On an iPhone, Home's gear, ⋯, *Undo*, *Share*, the recording screen's X and every other round button act when you lift your finger, also after a long press. A long press no longer shows a name bubble, and a held picture in a note no longer shows its file name: a held picture opens when you lift. VoiceOver and the check still find each button by its name. *New note* keeps its own hold: a hold still records a voice note. Android and the web page stay as they are today.
  ```picture
  Today, hold the gear 1 second: pictures/today.png
  After, hold the gear 1 second: pictures/after.png
  ```
- **The check needs no second tap.** The Settings step stays as it is: one tap on the gear. A second tap in the check would only hide the fault, and a person would still get it.
- **The guides say it.** The website's Settings page says a long press on the gear opens Settings too. The device check's guide says the fix, so a later slow tap is not taken for a broken app.

Non-goals: no change to *New note*'s hold to talk, no change on Android or the web page, and no new tour step.

## What the build needs

- **Nothing.** A screen test proves a 1-second press opens Settings, and the next device check runs the Settings step on a real iPhone simulator.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-home-screen`: the Settings button opens Settings however long the press.
- `relay-brand`: on an iPhone, every app button acts when the finger lifts, and a long press shows no name bubble.

## Impact

- Phone: `mobile/lib/app.dart` (the iPhone theme sets `TooltipThemeData(triggerMode: TooltipTriggerMode.manual)`).
- Tests: `mobile/test/screens_test.dart` (a 1-second press on the gear opens Settings on iOS; Android keeps the bubble).
- Docs: `site/src/content/docs/app/settings.md`, `wiki/development/device-check-tour.md`.

## Decision log

- **2026-11-12** — Assumed: fix the app, not the check's flow, because a screen test showed a 1-second press opens nothing today and opens Settings with the change, while a second tap in the flow fails again whenever the slow Mac holds that tap too, and a person would still get the fault.
- **2026-11-12** — Assumed: all round buttons on iPhone, not only the gear, because iPhone buttons open on lift and show no name bubble, the recording screen's X had the same miss on 2026-11-09, and one theme line covers every named button.
- **2026-11-12** — Assumed: Android and the web page keep the bubble, because on Android a long press shows a button's name, and a mouse on the web shows it on hover.
- **2026-11-12** — Assumed: *New note* keeps its hold to talk, because the hold is its own action, not a name bubble.
- **2026-11-12** — Assumed: a held picture in a note, or a note row's small picture, shows no file name on an iPhone either, because the review found the same theme setting covers them, and iPhone apps show no name bubble there too.
- **2026-11-12** — Checkpoint: built the iPhone theme setting, two screen tests and both guides; the review fixed the website sentence to name the gear only. The device check is next.
