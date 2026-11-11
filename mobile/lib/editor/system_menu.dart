import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// The note editor's text menu: the iPhone's own where iOS can show it (iOS 16 and later, while the keyboard is
/// attached), else the editor's drawn copy. The system's *Paste* needs no *Allow Paste?* question.
Widget noteContextMenu(BuildContext context, QuillRawEditorState editor) =>
  SystemContextMenu.isSupported(context) && editor.hasConnection
  ? QuillSystemMenu(editor: editor)
  : QuillRawEditorConfig.defaultContextMenuBuilder(context, editor);

/// The iPhone's own text menu for a Quill editor, as Flutter's `SystemContextMenu` shows it for a `TextField`, whose
/// factory needs an `EditableTextState` that Quill does not have.
class QuillSystemMenu extends StatefulWidget {
  const QuillSystemMenu({super.key, required this.editor});

  final QuillRawEditorState editor;

  /// The system items for the editor's own buttons, as `SystemContextMenu.getDefaultItems` maps them, but Cut, Copy and
  /// Select All run the editor's own actions on its own selection. The phone's own Cut, Copy and Select All work on the
  /// phone's copy of the words, and on an iPhone their Select All selected nothing. Paste stays the phone's own, so the
  /// phone asks no *Allow Paste?* question for words from another app.
  ///
  /// With no words selected, the menu leaves out the items that act on a selection: the editor offers *Cut* and *Copy*
  /// even then, and the iPhone's own menu never does.
  static List<IOSSystemContextMenuItem> itemsOf(QuillRawEditorState editor, CupertinoLocalizations words) => [
    for (final button in editor.contextMenuButtonItems)
      if (!editor.textEditingValue.selection.isCollapsed || !_needsSelection.contains(button.kind))
      ?switch (button.kind) {
        ContextMenuButtonKind.cut => _own(words.cutButtonLabel, button),
        ContextMenuButtonKind.copy => _own(words.copyButtonLabel, button),
        ContextMenuButtonKind.paste => const IOSSystemContextMenuItemPaste(),
        ContextMenuButtonKind.selectAll => _own(words.selectAllButtonLabel, button, () => _reopenAfterClose(editor)),
        ContextMenuButtonKind.lookUp => const IOSSystemContextMenuItemLookUp(),
        ContextMenuButtonKind.searchWeb => const IOSSystemContextMenuItemSearchWeb(),
        ContextMenuButtonKind.share => const IOSSystemContextMenuItemShare(),
        ContextMenuButtonKind.liveTextInput => const IOSSystemContextMenuItemLiveText(),
        _ => null,
      },
  ];

  /// The items that act on the selected words.
  static const _needsSelection = {ContextMenuButtonKind.cut, ContextMenuButtonKind.copy, ContextMenuButtonKind.lookUp,
    ContextMenuButtonKind.searchWeb, ContextMenuButtonKind.share};

  /// An item with the system's look that runs [button]'s own action, after [before].
  static IOSSystemContextMenuItem? _own(String title, ContextMenuButtonItem button, [void Function()? before]) =>
    switch (button.onPressed) {
      final pressed? => IOSSystemContextMenuItemCustom(title: title, onPressed: () {
        before?.call();
        pressed();
      }),
      null => null,
    };

  /// For each editor, whether the menu opens again once the system has closed it.
  static final _reopen = Expando<bool>();

  /// After Select All the menu opens again, as in Apple Notes, so Cut and Copy are one tap away. The system closes its
  /// menu after each item, and that news can come before or after the item's action.
  static void _reopenAfterClose(QuillRawEditorState editor) {
    if (closedJustNow(editor)) {
      _reopenSoon(editor);
    } else {
      _reopen[editor] = true;
    }
  }

  /// Opens [editor]'s menu after the frame, when the editor has drawn the new selection the menu points at.
  static void _reopenSoon(QuillRawEditorState editor) {
    _reopen[editor] = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (editor.mounted && !editor.textEditingValue.selection.isCollapsed) editor.showToolbar();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// The selection's box on the screen, which the menu points at. The endpoints come first to last, so the line
  /// heights do too: a selection made backwards from the words up into the title still clears the title's letters.
  static Rect anchorOf(QuillRawEditorState editor) {
    final render = editor.renderEditor;
    final selection = editor.textEditingValue.selection;
    return TextSelectionToolbarAnchors.getSelectionRect(render,
      render.preferredLineHeight(TextPosition(offset: selection.start)),
      render.preferredLineHeight(TextPosition(offset: selection.end)), render.getEndpointsForSelection(selection));
  }

  /// How long after the system closes the menu a tap on the cursor still opens nothing.
  static const closeWindow = Duration(milliseconds: 300);

  /// For each editor, a timer that runs for [closeWindow] after the system closed its menu.
  static final _closedBySystem = Expando<Timer>();

  /// Whether the system closed [editor]'s menu in the last [closeWindow]. On an iPhone a touch outside the menu closes
  /// it at touch down, so the tap on the cursor that closed it must not open it again at touch up.
  static bool closedJustNow(EditorState editor) => _closedBySystem[editor]?.isActive ?? false;

  @override
  State<QuillSystemMenu> createState() => _QuillSystemMenuState();
}

class _QuillSystemMenuState extends State<QuillSystemMenu> {
  late final _menu = SystemContextMenuController(onSystemHide: () {
    final editor = widget.editor;
    QuillSystemMenu._closedBySystem[editor]?.cancel();
    QuillSystemMenu._closedBySystem[editor] = Timer(QuillSystemMenu.closeWindow, () {});
    editor.hideToolbar(false);
    if (QuillSystemMenu._reopen[editor] ?? false) QuillSystemMenu._reopenSoon(editor);
  });

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The iPhone's own words for the app's items, such as *Select All*, not Flutter's shared *Select all*.
    final items = QuillSystemMenu.itemsOf(widget.editor, CupertinoLocalizations.of(context));
    if (items.isNotEmpty) {
      final words = WidgetsLocalizations.of(context);
      _menu.showWithItems(QuillSystemMenu.anchorOf(widget.editor), [for (final item in items) item.getData(words)]);
    }
    return const SizedBox.shrink();
  }
}
