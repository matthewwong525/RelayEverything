# Paste in a note feels like the iPhone's own

**Status:** ready-to-ship
**Branch:** grumpy-rabbit
**Open questions:** none

## Why

When you type a note and hold to paste, the menu that comes up is a copy of the iPhone's menu, not the real one. It looks a little wrong, it shows no magnifier while you drag the cursor, a tap on the cursor does not open it, and a paste of words from another app asks *Allow Paste?* each time. You want it to work as in Apple Notes.

## What Changes

- **The iPhone's own menu.** Hold in a note, or select words, and the iPhone's own menu comes up: *Paste*, *Copy*, *Cut*, *Select All*, *Look Up*, *Search Web* and *Share*, as each fits, in the iPhone's own look, with the iPhone's own words in your language.
  ```picture
  Before, a hold today: pictures/before-hold.png
  ```
  Today the app draws its own copy of the menu, and it covers the note's title. The picture comes from the app's real screen on this computer; the menu's words show as black blocks because the test can't draw the iPhone's own font.
  ```screen
  <div class="card col gap phone">
    <span class="muted">After: the iPhone's own menu</span>
    <div class="row gap"><span class="tag">Paste</span><span class="tag">Select All</span><span class="tag">AutoFill</span><span class="tag">›</span></div>
    <span>Buy milk and |</span>
    <span class="muted">Same menu as in Apple Notes</span>
  </div>
  ```
  No real picture: the iPhone's own menu, which only an iPhone draws; the device check takes it at /verify.

- **Paste asks nothing.** A tap on *Paste* puts in words you copied in another app at once, with no *Allow Paste?* question. Pasted words come in as plain text, in the note's own style, as in Apple Notes when you paste from a web page.
  ```mermaid
  sequenceDiagram
    participant You
    participant App as Your note
    You->>App: Copy in Safari, hold in note
    App-->>You: iPhone's menu
    You->>App: Paste
    App-->>You: Words in, no question
  ```

- **A magnifier while you move the cursor.** Hold and drag, or drag a selection handle, and the iPhone's round magnifier shows the words under your finger, above the line, with a rim in the app's green, as the cursor is. Android shows its own magnifier.
  ```picture
  After, dragging the cursor: pictures/after-magnifier.png
  ```

- **Tap the cursor to open the menu.** While you type, a tap on the blinking cursor opens the menu, and a second tap closes it, as in Apple Notes. A tap anywhere else still moves the cursor there, and a tap on a link still puts the cursor in it.
  ```picture
  Before, a tap on the cursor today: pictures/before-tap.png
  ```
  Today a tap on the cursor shows nothing.
  ```mermaid
  flowchart LR
    T["Tap"] --> Q{"On cursor?"}
    Q -- yes --> M["Menu on or off"]
    Q -- no --> C["Cursor moves"]
  ```

- **Other phones and the browser stay as they are.** Where the iPhone's own menu can't show, the app keeps its own menu.
  | Where | Menu | Magnifier |
  |---|---|---|
  | iPhone, iOS 16 and later | the iPhone's own | yes |
  | Older iPhone | the app's copy, as today | yes |
  | Android | the app's Android menu, as today | yes |
  | Browser | the browser's own, as today | no |

- **The website says so.** The page on your notes says you hold or tap the cursor for the iPhone's menu, and that pasted words come in as plain text.

Non-goals: no new menu items of our own, such as text styles in the menu; no change to the ⋯ menu's *Copy*; no paste of pictures or files from the menu; no change to the notes list or the voice player, which another plan changes.

## What the build needs

- **Nothing.** No key or login. The device check runs on GitHub's Macs with the key it already has.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-note-editing`: a new requirement for the text menu in the note editor: the system menu on iOS, paste with no prompt, plain-text paste, a magnifier, and a tap on the cursor that opens the menu.

## Impact

- Phone: `mobile/lib/screens/note_editor.dart` (`QuillEditorConfig.contextMenuBuilder`, `quillMagnifierBuilder`, `_tapUp`); a new small file `mobile/lib/editor/system_menu.dart` for the system menu widget; tests in `mobile/test/screens_test.dart` or a new `mobile/test/paste_menu_test.dart`; a new tour step `mobile/device-check/flows/paste-menu.yaml`.
- Docs: `site/src/content/docs/app/your-notes.md`.
- Dependencies: none new. Uses Flutter 3.47.9's `SystemContextMenuController` and flutter_quill 11.6.0's hooks.
- Overlap: the plan *One notes list, a voice player with sound waves, quieter sync status* also edits `note_editor.dart`; whichever publishes second catches up.

## Decision log

- **2026-11-11** — Asked (in the planning chat) whether to fix paste with the notes look or apart → chose its own plan and workspace.
- **2026-11-11** — Assumed: show the iPhone's own menu where iOS can (iOS 16 and later), and keep the app's menu elsewhere, because only the real menu looks and works as in Apple Notes, and older phones, Android and the browser have no such menu to call.
- **2026-11-11** — Assumed: pasted words come in as plain text, with no styles from the other app, because the iPhone's own *Paste* gives the editor plain text, and a note keeps only its own few styles.
- **2026-11-11** — Assumed: words copied with the iPhone's *Copy* inside a note also paste as plain text, so a checklist copied from one note pastes as plain lines, because the iPhone's menu copies plain text; the ⋯ menu's *Copy* already copies plain words.
- **2026-11-11** — Assumed: a tap on the cursor opens the menu and a second tap closes it, as in Apple Notes and the iPhone's own text fields.
- **2026-11-11** — Assumed: add the magnifier on Android too, because Android shows one in its own text fields; the browser gets none, as the browser draws its own.
- **2026-11-11** — Asked (at /apply) to draw the real app, not a sketch → *Before* pictures now come from a screen test of the real note page; the iPhone's own menu stays a sketch until the device check draws it.
- **2026-11-11** — Assumed: the menu keeps the iPhone's standard items and adds none of our own, because the person asked for the iPhone's own feel, and *Aa* already sits above the keyboard.
- **2026-11-11** — Assumed: the tour step taps the words, then holds, in place of a tap on the cursor, because a flow can't find the blinking cursor; the widget tests and the device check's scenario cover the tap on the cursor.
- **2026-11-11** — Assumed: the menu always offers *Paste* on a phone, because the editor checks no clipboard there; the iPhone itself decides whether its *Paste* can act, and nothing reads the clipboard before the tap.
- **2026-11-11** — Assumed: the iPhone's own menu shows only while the keyboard is attached to the note, else the app's own menu, because the iPhone's menu acts on the keyboard's text and Flutter refuses it with none.
- **2026-11-11** — Assumed (review): the menu's anchor takes the line heights from the selection's start and end, not its base and extent, because the endpoints come first to last, and a selection made backwards from the words into the title pointed the menu into the title's letters.
- **2026-11-11** — Assumed (review): the tour step no longer claims to prove paste with no *Allow Paste?* question, because its copy comes from the same app, so iOS never asks; the device check's `xcrun simctl pbcopy` scenario checks it.
- **2026-11-11** — Assumed (review): the iPhone lens's rim takes the app's tint (the green of the cursor), not Flutter's fixed blue, because the iPhone's own lens and Flutter's `CupertinoTextMagnifier` take the tint; seen in the screen-test picture.
- **2026-11-11** — Assumed (review): the magnifier is our own, Flutter's `CupertinoMagnifier` on iOS and Material `Magnifier` on Android, because flutter_quill's default is a plain 100x45 box with an offset grey shadow, not the iPhone's capsule. It shows in the page's overlay, centred above the finger's line and inside the screen, because the editor's `Stack` clips a lens above the first line.
- **2026-11-11** — Assumed (review): for 300 ms after the iPhone closes its menu, a tap on the cursor opens nothing, because a touch outside the menu may close it at touch down, and the same tap's touch up would open it again. A timer marks the 300 ms in place of a clock time, because the app has no `clock` package and a timer runs on the tests' fake time.
- **2026-11-11** — Saved for the iPhone check (3.2): all other tasks done; 741 phone tests and the analyzer pass; a second look found two problems, both fixed, then none. The same save carries a wiki page, `wiki/development/phone-pictures.md`, linked from the plan skill, `wiki/review-pages.md` and `.agents/rules/mobile.md`, because Matthew asked that plans show the real phone app, not a sketch; WongStack gets the general fix in its own workspace, *Real app pictures in plans, not sketches*.
- **2026-11-11** — Fixed after the iPhone check (3.2) came back broken: the phone's own *Select All* selected nothing, so the tour found no *Copy*. *Cut*, *Copy* and *Select All* now run the editor's own actions inside the iPhone's menu, with the iPhone's words and look; *Paste* stays the phone's own, so it still asks no question. After *Select All* the menu opens again, as in Apple Notes.
- **2026-11-11** — Second iPhone check: the tour passed, with *Select All*, *Copy* and *Paste* on the iPhone; Claude's own check hung and gave no verdict. Its pictures showed *Cut* and *Copy* after a hold with no words selected, because the editor offers them even then; the menu now leaves them out. Asked Matthew: fix this, then check again.
- **2026-11-11** — Third iPhone check: the paste step passed again; the Settings step failed on a tap on the gear, which this change does not touch, and Claude did not start. Caught up with main, which published the other part of the request (one notes list, a voice player, quieter sync status) in the same editor file, so one more check covers both.
- **2026-11-11** — Fourth iPhone check, on the version caught up with main: works. The tour passed, with Select All, Copy and Paste; Claude saw the iPhone's own menu with Paste and Select All on a hold, a paste of words put on the simulator's clipboard with no *Allow Paste?* question, and a tap on the cursor that opens and closes the menu (the iPhone put it below the cursor). The magnifier could not be checked on the simulator, because a flow can't take a picture during a drag; the phone tests cover it. Task 3.2 ticked; a paste from Safari on Matthew's iPhone after TestFlight is still to try.
- **2026-11-11** — Archived for publishing, after the fourth iPhone check passed. The spec was already brought up to date on main's version, so the archive keeps it as it is.
