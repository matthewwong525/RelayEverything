# No grey box when you tap a Home section name

**Status:** ready-to-ship
**Branch:** stop-tap-visual-feedback
**Open questions:** none

## Why

On Home, a tap on *On this phone* or *Connections* folds that section. The tap also shows a large grey box behind the name. Apple Notes shows no box when you fold a section, and the box looks like a fault.

## What Changes

- **What you see.** A tap on *On this phone* or *Connections* folds or opens the section, and only the chevron turns. No grey box shows behind the name. The folder rows (*Notes*, *Sending* and the others) keep their tap shade, because a row opens a page.
  ```text
  Before                          After
  ------                          -----
  [######## Connections ####v]    Connections                v
  grey box while you tap          no box; the chevron turns
  ```
- **What is left out, and why.** No Relay Everything website page changes, because the website does not describe how a tap looks.

## What the build needs

- **Flutter on this computer**: Ready, for the phone app's tests.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-home-screen`: a tap on a section name folds it with no highlight.

## Impact

- `mobile/lib/screens/home.dart`: `_FoldHeader` drops its `InkWell` for a plain tap target.
- `mobile/test/screens_test.dart`: the fold test also checks that the header has no ink.
- Non-goals: no change to folder rows, to what folds, or to the saved fold state.

## Decision log

- **2026-11-08** — Assumed: only the section names lose the tap shade, not the folder rows, because the person pointed at the *Connections* name, and Apple Notes shades a row that opens a page.
- **2026-11-08** — Archived and saved for publish: the header uses a plain tap target; `flutter test` (399) and `flutter analyze` pass. No second-look review ran, because the change is three lines.
