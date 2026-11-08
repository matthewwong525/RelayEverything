import 'dart:math';

import 'package:flutter/material.dart';

/// *‹ Home* or *‹ Voice notes* at the top left of a page, as Apple Notes has it: it names the page it goes back to. Its
/// tooltip is *Back*, the name screen readers and tests know.
class BackTo extends StatelessWidget {
  const BackTo(this.label, {super.key});

  final String label;

  /// The width an app bar gives the button for [label].
  static double widthOf(String label) => max(104, 52 + label.length * 9.5);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.chevron_left, size: 28),
        label: Text(label, maxLines: 1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 4, right: 8)),
      ),
    );
  }
}
