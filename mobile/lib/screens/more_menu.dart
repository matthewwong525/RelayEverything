import 'dart:math';

import 'package:flutter/material.dart';

import '../brand.dart';

/// One item of a [MoreMenu]: its word, its icon, and what a tap does.
typedef MoreItem = (String label, IconData icon, VoidCallback onPressed);

/// A ⋯ menu as an iPhone draws it: its right edge in line with the button's, at least [MoreMenu.margin] in from each
/// side of the screen, with round corners on the card color. A bare `MenuAnchor` opens from the button's left edge, so
/// near the right edge of the screen it runs off and Flutter pushes it flush against the edge.
class MoreMenu extends StatefulWidget {
  const MoreMenu({super.key, required this.items, this.destructive, required this.builder});

  final List<MoreItem> items;
  /// An item that deletes, such as *Delete*: last, in the danger color, as Apple draws it.
  final MoreItem? destructive;
  /// The button: a tap on it calls `toggle`, which opens the menu, or closes it when it is open.
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  /// The menu's width: wide enough for the longest word, as Apple's pull-down menus are.
  static const width = 220.0;
  /// The menu stays this far in from the edge of the screen.
  static const margin = 12.0;
  /// The space between the button and the menu.
  static const gap = 6.0;

  @override
  State<MoreMenu> createState() => _MoreMenuState();
}

class _MoreMenuState extends State<MoreMenu> {
  final _menu = MenuController();

  /// Opens the menu under the button, its right edge on the button's right edge, moved in to keep [MoreMenu.margin]
  /// from the screen's edges.
  void _toggle(BuildContext anchor) {
    if (_menu.isOpen) return _menu.close();
    final button = anchor.findRenderObject()! as RenderBox;
    final left = button.localToGlobal(Offset.zero).dx;
    final screen = MediaQuery.sizeOf(anchor).width;
    final x = max(MoreMenu.margin - left,
      min(button.size.width - MoreMenu.width, screen - MoreMenu.margin - left - MoreMenu.width));
    _menu.open(position: Offset(x, button.size.height + MoreMenu.gap));
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(brand.card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.3)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
        minimumSize: const WidgetStatePropertyAll(Size(MoreMenu.width, 0)),
        maximumSize: const WidgetStatePropertyAll(Size(MoreMenu.width, double.infinity)),
      ),
      menuChildren: [
        for (final item in widget.items) _item(item, brand.muted, brand.ink),
        if (widget.destructive case final item?) _item(item, brand.danger, brand.danger),
      ],
      builder: (anchor, _, _) => widget.builder(anchor, () => _toggle(anchor)),
    );
  }

  // A menu's items keep their own width; each fills the menu, so its press fills the row.
  Widget _item(MoreItem item, Color icon, Color ink) => SizedBox(width: MoreMenu.width, child: MenuItemButton(
    leadingIcon: Icon(item.$2, size: 20, color: icon),
    onPressed: item.$3,
    child: Text(item.$1, style: TextStyle(fontSize: 16, color: ink)),
  ));
}
