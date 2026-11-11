# Design

## Context

- **The editor.** `mobile/lib/screens/note_editor.dart` shows a `QuillEditor` (flutter_quill 11.6.0, Flutter 3.47.9) with `QuillEditorConfig(onTapUp: _tapUp, ...)`. It sets no `contextMenuBuilder` and no `quillMagnifierBuilder`.
- **Today's menu.** flutter_quill's `RawEditorConfig.defaultContextMenuBuilder` draws `AdaptiveTextSelectionToolbar.buttonItems` from `QuillRawEditorState.contextMenuButtonItems`: a Flutter copy of the iPhone menu. Its *Paste* calls `Clipboard.getData` itself, so iOS 16+ asks *Allow Paste?* for text another app copied. `kIsWeb` makes `showToolbar()` return false, so the browser shows its own.
- **Tap.** `QuillEditorSelectionGestureDetectorBuilder.onSingleTapUp` (`editor.dart`) calls `config.onTapUp` first; when that returns true it stops. Otherwise it calls `hideToolbar()` and moves the cursor, so a tap on the cursor never opens the menu. `_tapUp` today returns false while the editor has focus, and opens a link when it does not.
- **Magnifier.** `QuillEditorConfig.quillMagnifierBuilder` is null by default; `defaultQuillMagnifierBuilder` gives a `QuillMagnifier`.
- **System menu.** `SystemContextMenu.isSupported(context)` is true on iOS when `MediaQuery.supportsShowingSystemContextMenu` is (iOS 16+). The `SystemContextMenu` widget's own constructor is private and its `editableText` factory needs an `EditableTextState`, which Quill does not have. `SystemContextMenuController` is public: `showWithItems(Rect, List<IOSSystemContextMenuItemData>)`, `hide()`, `dispose()`, and an `onSystemHide` callback. The system's *Paste*, *Cut*, *Copy* and *Select All* act on the engine's text input view, which Quill feeds through its `TextInputConnection` (`raw_editor_state_text_input_client_mixin.dart`): a paste comes back as `updateEditingValue`, which Quill turns into a plain-text insert.

## Goals / Non-Goals

**Goals:** the real iPhone menu wherever iOS offers it; no paste prompt; a magnifier; a tap on the cursor toggles the menu; nothing changes where the system menu can't show.

**Non-Goals:** menu items of our own beyond the standard ones; rich paste between notes; a change to the ⋯ menu's *Copy*; a fork or patch of flutter_quill.

## Decisions

- **A small widget for the system menu.** Add `mobile/lib/editor/system_menu.dart` with `QuillSystemMenu`, a `StatefulWidget` that takes the `QuillRawEditorState`. It owns one `SystemContextMenuController(onSystemHide: () => editor.hideToolbar(false))`, calls `showWithItems` in `didChangeDependencies`/`didUpdateWidget` with the selection rect and the items, and `hide()` + `dispose()` in `dispose`. It mirrors Flutter's private `_SystemContextMenuState`, so its behavior stays the same as a `TextField`'s. Alternative: patch flutter_quill to expose an `EditableTextState`, rejected because a fork is ours to keep up to date.
- **The anchor.** The rect comes from `TextSelectionToolbarAnchors.getSelectionRect(editor.renderEditor, startGlyphHeight, endGlyphHeight, editor.renderEditor.getEndpointsForSelection(selection))`, translated to global, as `SystemContextMenu.editableText` does. When `getSelectionRect` can't take a `RenderEditor` (it wants a `RenderBox`, which `RenderEditor` is), fall back to `editor.contextMenuAnchors.primaryAnchor` with the cursor's height.
- **The items.** Map `editor.contextMenuButtonItems` by `ContextMenuButtonKind`: *Paste*, *Look Up*, *Search Web*, *Share* and *Live Text* to the phone's own `IOSSystemContextMenuItemPaste`, `LookUp`, `SearchWeb`, `Share` and `LiveText`; *Cut*, *Copy* and *Select All* to an `IOSSystemContextMenuItemCustom` with the iPhone's title from `CupertinoLocalizations` that runs the editor's own button. The phone's own *Cut*, *Copy* and *Select All* act on the engine's copy of the words, and on the iPhone check (3.2) its *Select All* selected nothing; the editor's own act on its own selection. *Paste* stays the phone's own, so iOS asks no *Allow Paste?* question. After *Select All* the menu opens again, as in Apple Notes, once the phone has closed it: the phone sends the item's action before it says it closed the menu, and Flutter drops an action that comes after. Quill's *Paste* item shows only when its clipboard check says text is there; that check reads `Clipboard.hasStrings`, which iOS answers with no prompt. When the list is empty, show nothing.
- **Which menu.** `contextMenuBuilder: (context, editor) => SystemContextMenu.isSupported(context) ? QuillSystemMenu(editor: editor) : RawEditorConfig.defaultContextMenuBuilder(context, editor)`. The browser never reaches it (`showToolbar` returns false on web).
- **Paste is the system's.** The system *Paste* goes to the engine's text input view, not to Quill's `pasteText`, so the user-tapped paste gives no prompt and arrives as plain text. Quill's rich paste (`_pasteDelta` when the clipboard matches its last copy) does not run on iOS 16+; a copy inside a note pastes plain. This is the settled plain-text choice.
- **Tap on the cursor.** In `_tapUp`, while the editor has focus and `_formatting` is false: when the selection is collapsed and `positionOf(details.globalPosition).offset == _controller.selection.baseOffset`, toggle the menu through the raw editor: give `QuillEditor` a `GlobalKey<QuillEditorState>`, whose `editableTextKey.currentState` is the `QuillRawEditorState`: `hideToolbar()` when its `selectionOverlay?.toolbar` is showing, else `showToolbar()`, and return true. Otherwise return false, as today, so Quill moves the cursor. iOS taps place the cursor at a word edge, so a tap inside the same word after the cursor is not a match; that is how Apple Notes acts too, where only a tap on the cursor itself toggles.
- **Magnifier.** `quillMagnifierBuilder: relay.web ? null : noteMagnifier`, from `mobile/lib/editor/magnifier.dart`: Flutter's `CupertinoMagnifier` on iOS and Material `Magnifier` on Android, centred above the finger's line in the page's overlay, inside the screen. Quill's `defaultQuillMagnifierBuilder` draws a plain 100x45 box with an offset grey shadow, not the iPhone's capsule.

## Risks / Trade-offs

- [The system menu and Quill's state disagree, such as a menu left open after the note page closes] → the widget hides the menu in `dispose`, and `onSystemHide` tells Quill the menu is gone; a widget test checks both platform calls.
- [The system's *Paste* or *Cut* does not reach Quill if its text input connection is closed] → the menu shows only while the editor has focus and an open connection; the device check pastes, cuts and copies on a simulator.
- [A widget test can't show the real menu] → tests check the platform message (`ContextMenu.showSystemContextMenu` with its items) on a fake iOS with `supportsShowingSystemContextMenu: true`; the device check and a TestFlight try check the look.
- [Styles lost when copying inside a note] → accepted; see the Decision log.

## Migration Plan

No data changes. A rollback is one revert of the editor change.
