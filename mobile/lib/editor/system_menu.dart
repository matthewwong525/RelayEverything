import 'dart:async';

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

  /// The system items for the editor's own buttons, as `SystemContextMenu.getDefaultItems` maps them.
  static List<IOSSystemContextMenuItem> itemsOf(QuillRawEditorState editor) => [
    for (final button in editor.contextMenuButtonItems)
      ?switch (button.kind) {
        ContextMenuButtonKind.copy => const IOSSystemContextMenuItemCopy(),
        ContextMenuButtonKind.cut => const IOSSystemContextMenuItemCut(),
        ContextMenuButtonKind.paste => const IOSSystemContextMenuItemPaste(),
        ContextMenuButtonKind.selectAll => const IOSSystemContextMenuItemSelectAll(),
        ContextMenuButtonKind.lookUp => const IOSSystemContextMenuItemLookUp(),
        ContextMenuButtonKind.searchWeb => const IOSSystemContextMenuItemSearchWeb(),
        ContextMenuButtonKind.share => const IOSSystemContextMenuItemShare(),
        ContextMenuButtonKind.liveTextInput => const IOSSystemContextMenuItemLiveText(),
        _ => null,
      },
  ];

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
  });

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = QuillSystemMenu.itemsOf(widget.editor);
    if (items.isNotEmpty) {
      final words = WidgetsLocalizations.of(context);
      _menu.showWithItems(QuillSystemMenu.anchorOf(widget.editor), [for (final item in items) item.getData(words)]);
    }
    return const SizedBox.shrink();
  }
}
