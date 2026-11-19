import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart'
  show AdaptiveTextSelectionToolbar, Brightness, MaterialTapTargetSize, NoSplash, TextButton, Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:follow_the_leader/follow_the_leader.dart' show LeaderLink;
import 'package:overlord/follow_the_leader.dart' show LeaderMenuFocalPoint;
import 'package:overlord/overlord.dart' show CupertinoPopoverToolbar;
import 'package:super_editor/super_editor.dart';

import 'shortcuts.dart';

/// The format items of the computer's right-click menu on selected words.
const formatMenuItems = [
  ('Bold', FormatAction.bold), ('Italic', FormatAction.italic), ('Underline', FormatAction.underline),
  ('Strikethrough', FormatAction.strikethrough), ('Highlight', FormatAction.highlight), ('Link…', FormatAction.link),
];

/// What a note's text menu does: the note's own Cut, Copy, Paste and Select All, which keep its styles, tables and
/// files.
class NoteMenuActions {
  const NoteMenuActions({required this.hasSelection, required this.cut, required this.copy, required this.paste,
    required this.selectAll, required this.selectionChanges});

  /// Whether words are selected, not only a cursor.
  final bool Function() hasSelection;
  final VoidCallback cut;
  final VoidCallback copy;
  final VoidCallback paste;
  final VoidCallback selectAll;
  /// Tells of each change of the selection, so a drawn menu shows Cut and Copy once words are selected.
  final Listenable selectionChanges;
}

/// The computer's right-click menu at [anchor]: Cut, Copy, Paste and Select All, and with [format], on selected words,
/// *Bold*, *Italic*, *Underline*, *Strikethrough*, *Highlight* and *Link…*. A pick closes the menu.
Widget noteContextMenu(BuildContext context, {required Offset anchor, required NoteMenuActions actions,
    required VoidCallback close, void Function(FormatAction action)? format}) {
  final picked = actions.hasSelection();
  ContextMenuButtonItem item(ContextMenuButtonType type, VoidCallback onPressed, [String? label]) =>
    ContextMenuButtonItem(type: type, label: label, onPressed: () {
      close();
      onPressed();
    });
  final pick = format;
  return TextFieldTapRegion(child: AdaptiveTextSelectionToolbar.buttonItems(
    anchors: TextSelectionToolbarAnchors(primaryAnchor: anchor),
    buttonItems: [
      if (picked) item(ContextMenuButtonType.cut, actions.cut),
      if (picked) item(ContextMenuButtonType.copy, actions.copy),
      item(ContextMenuButtonType.paste, actions.paste),
      item(ContextMenuButtonType.selectAll, actions.selectAll),
      if (picked && pick != null)
        for (final (label, action) in formatMenuItems) item(ContextMenuButtonType.custom, () => pick(action), label),
    ],
  ));
}

/// The note's iPhone text menu, as super_editor's iPhone controls build it: the iPhone's own menu where iOS can show
/// it (iOS 16 and later), else a drawn copy. The system's *Paste* needs no *Allow Paste?* question.
DocumentFloatingToolbarBuilder noteIosToolbar(NoteMenuActions actions, SuperEditorIosControlsController Function() controls) =>
  (context, key, focalPoint) {
    if (IOSSystemContextMenu.isSupported(context)) {
      return NoteSystemMenu(focalPoint: focalPoint, actions: actions, controls: controls());
    }
    void then(VoidCallback action) {
      action();
      controls().hideToolbar();
    }
    return ListenableBuilder(
      listenable: actions.selectionChanges,
      builder: (context, _) => NoteDrawnIosMenu(
        menuKey: key,
        focalPoint: focalPoint,
        items: [
          if (actions.hasSelection()) ('Cut', () => then(actions.cut)),
          if (actions.hasSelection()) ('Copy', () => then(actions.copy)),
          ('Paste', () => then(actions.paste)),
          // As on the iPhone's own menu, the menu stays after Select All, now with Cut and Copy.
          ('Select All', actions.selectAll),
        ],
      ),
    );
  };

/// The iPhone's text menu drawn by the app where iOS shows none of its own (iOS 15): super_editor's
/// `IOSTextEditingFloatingToolbar`, which has no Select All, made again with [items].
class NoteDrawnIosMenu extends StatelessWidget {
  const NoteDrawnIosMenu({super.key, this.menuKey, required this.focalPoint, required this.items});

  /// The key super_editor knows the menu by.
  final Key? menuKey;
  final LeaderLink focalPoint;
  /// Each item's words and what it does, left to right.
  final List<(String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CupertinoPopoverToolbar(
      key: menuKey,
      focalPoint: LeaderMenuFocalPoint(link: focalPoint),
      elevation: 8,
      backgroundColor: dark ? const Color(0xFF333333) : const Color(0xFFFFFFFF),
      activeButtonTextColor: dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      inactiveButtonTextColor: dark ? const Color(0xFF757575) : const Color(0xFF999999),
      children: [
        for (final (label, action) in items)
          TextButton(
            onPressed: action,
            style: TextButton.styleFrom(
              foregroundColor: dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
              minimumSize: const Size(48, 0),
              padding: EdgeInsets.zero,
              splashFactory: NoSplash.splashFactory,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
            ),
          ),
      ],
    );
  }
}

/// The note's Android text menu: the note's own Cut, Copy, Paste and Select All.
DocumentFloatingToolbarBuilder noteAndroidToolbar(NoteMenuActions actions,
    SuperEditorAndroidControlsController Function() controls) =>
  (context, key, focalPoint) {
    void then(VoidCallback action) {
      action();
      controls().hideToolbar();
    }
    return ListenableBuilder(
      listenable: actions.selectionChanges,
      builder: (context, _) => AndroidTextEditingFloatingToolbar(
        floatingToolbarKey: key,
        focalPoint: focalPoint,
        onCutPressed: actions.hasSelection() ? () => then(actions.cut) : null,
        onCopyPressed: actions.hasSelection() ? () => then(actions.copy) : null,
        onPastePressed: () => then(actions.paste),
        onSelectAllPressed: actions.selectAll,
      ),
    );
  };

/// The iPhone's own text menu for a note, as Flutter's `SystemContextMenu` shows it for a `TextField`.
class NoteSystemMenu extends StatefulWidget {
  const NoteSystemMenu({super.key, required this.focalPoint, required this.actions, required this.controls});

  final LeaderLink focalPoint;
  final NoteMenuActions actions;
  final SuperEditorIosControlsController controls;

  /// The system items. Cut, Copy and Select All run the note's own actions on its own selection, as the phone's own
  /// work on the phone's copy of the words. Paste stays the phone's own, so the phone asks no *Allow Paste?* question
  /// for words from another app. With no words selected, the items that act on a selection stay out, as in Apple's
  /// own menu.
  static List<IOSSystemContextMenuItem> itemsOf(NoteMenuActions actions, CupertinoLocalizations words,
      {VoidCallback? reopen}) {
    final picked = actions.hasSelection();
    return [
      if (picked) IOSSystemContextMenuItemCustom(title: words.cutButtonLabel, onPressed: actions.cut),
      if (picked) IOSSystemContextMenuItemCustom(title: words.copyButtonLabel, onPressed: actions.copy),
      const IOSSystemContextMenuItemPaste(),
      IOSSystemContextMenuItemCustom(title: words.selectAllButtonLabel, onPressed: () {
        reopen?.call();
        actions.selectAll();
      }),
      if (picked) ...const [IOSSystemContextMenuItemLookUp(), IOSSystemContextMenuItemSearchWeb(),
        IOSSystemContextMenuItemShare()],
    ];
  }

  /// How long after the system closes the menu a tap on the cursor still opens nothing.
  static const closeWindow = Duration(milliseconds: 300);

  static Timer? _closedBySystem;

  /// Whether the system closed the menu in the last [closeWindow]. On an iPhone a touch outside the menu closes it at
  /// touch down, so the tap on the cursor that closed it must not open it again at touch up.
  static bool closedJustNow() => _closedBySystem?.isActive ?? false;

  @override
  State<NoteSystemMenu> createState() => _NoteSystemMenuState();
}

class _NoteSystemMenuState extends State<NoteSystemMenu> {
  /// After Select All the menu opens again, as in Apple Notes, so Cut and Copy are one tap away.
  bool _reopen = false;

  late final _menu = SystemContextMenuController(onSystemHide: () {
    NoteSystemMenu._closedBySystem?.cancel();
    NoteSystemMenu._closedBySystem = Timer(NoteSystemMenu.closeWindow, () {});
    final controls = widget.controls;
    controls.hideToolbar();
    if (_reopen) {
      _reopen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => controls.showToolbar());
      WidgetsBinding.instance.scheduleFrame();
    }
  });

  @override
  void initState() {
    super.initState();
    widget.focalPoint.addListener(_moved);
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  void didUpdateWidget(NoteSystemMenu old) {
    super.didUpdateWidget(old);
    if (old.focalPoint != widget.focalPoint) {
      old.focalPoint.removeListener(_moved);
      widget.focalPoint.addListener(_moved);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  void dispose() {
    widget.focalPoint.removeListener(_moved);
    _menu.dispose();
    super.dispose();
  }

  void _moved() => WidgetsBinding.instance.addPostFrameCallback((_) => _show());

  void _show() {
    final link = widget.focalPoint;
    final offset = link.offset, size = link.leaderSize;
    if (!mounted || offset == null || size == null) return;
    // The iPhone's own words for the app's items, such as *Select All*, not Flutter's shared *Select all*.
    final items = NoteSystemMenu.itemsOf(widget.actions, CupertinoLocalizations.of(context),
      reopen: () => _reopen = true);
    final words = WidgetsLocalizations.of(context);
    _menu.showWithItems(offset & size, [for (final item in items) item.getData(words)]);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
