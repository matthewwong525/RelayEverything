import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

/// *‹ Home* or *‹ Notes* at the top left of a page, as Apple Notes has it: it names the page it goes back to. Its
/// tooltip is *Back*, the name screen readers and tests know.
class BackTo extends StatelessWidget {
  const BackTo(this.label, {super.key, this.onPressed});

  final String label;
  /// Goes back where the browser's layout holds the page, in place of the page under it.
  final VoidCallback? onPressed;

  /// The width an app bar gives the button for [label].
  static double widthOf(String label) => max(104, 52 + label.length * 9.5);

  @override
  Widget build(BuildContext context) {
    var onPressed = this.onPressed;
    // The first page of a part of the Mac's window: back to Home on the phone's pages, else no back.
    final root = PartRoot.of(context);
    if (onPressed == null && root != null && !Navigator.of(context).canPop()) {
      onPressed = root.onBack;
      if (onPressed == null) return const SizedBox.shrink();
    }
    return Tooltip(
      message: 'Back',
      child: TextButton.icon(
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
        icon: const Icon(CupertinoIcons.chevron_back, size: 24),
        label: Text(label, maxLines: 1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 4, right: 8)),
      ),
    );
  }
}

/// Above a part of the Mac's window that holds the phone's pages, with their own [Navigator]: the first page's [BackTo]
/// calls [onBack], or shows nothing when it is null. The pages it opens go back as on the phone.
class PartRoot extends InheritedWidget {
  const PartRoot({super.key, this.onBack, required super.child});

  final VoidCallback? onBack;

  static PartRoot? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PartRoot>();

  @override
  bool updateShouldNotify(PartRoot oldWidget) => onBack != oldWidget.onBack;
}
