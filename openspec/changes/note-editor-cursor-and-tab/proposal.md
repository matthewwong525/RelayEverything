# Proposal

**Status:** in-progress
**Branch:** `note-editor-cursor-and-tab`
**Open questions:** none

## Why

On the web page and the Mac app, two things in a note do not work as you expect. In dark mode you can't see the typing cursor, so you don't know where your words will go. And when you select several list items, Tab and Shift+Tab move only the last one.

## What Changes

- **The cursor shows in dark mode.** On a computer, the typing cursor takes the colour of the words: dark on a light page, light on a dark page. Before, it was always black, so a dark page hid it.
  ```picture
  Before, dark page: pictures/cursor-before.png
  After, dark page: pictures/cursor-after.png
  ```
- **Tab and Shift+Tab move every selected line.** Select several list items and press Tab: all of them move one level in. Shift+Tab moves all of them back out. With no selection, Tab still moves only the line with the cursor.
  ```picture
  After Tab: pictures/tab-in.png
  After Shift+Tab: pictures/tab-out.png
  ```

## What the build needs

- **Nothing.**

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-note-editing`: the computer cursor shows on a dark page; Tab and Shift+Tab move every selected line.

## Impact

- Phone, Mac and web app (`mobile/`): `lib/screens/note_editor.dart` and `test/screens_test.dart`. The phone keeps its own cursor and handles.
- No server, API or data change. The website's notes page does not name the cursor colour or Tab, so it stays as it is.

## Decision log

- **2026-11-19** — Assumed: the cursor takes the words' colour (the theme's `onSurface`), not the accent green, because the person asked only to see it, and the words' colour shows in both modes.
- **2026-11-19** — Assumed: Tab with a selection moves every line it touches through the app's own indent command, the same one the Format sheet's indent buttons use, because the editor's built-in Tab acts on one line only.
- **2026-11-19** — Assumed: the code was written before this plan, because the person reported two bugs in a live screen; the plan records the fix and its checks.
- **2026-11-19** — Save: the two requirements join the main `relay-note-editing` spec; the preview is next, then publish.
