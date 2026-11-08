import 'package:flutter/material.dart';

/// The width an app bar gives [BackToNotes].
const backToNotesWidth = 104.0;

/// *‹ Notes* at the top left of a page opened from the notes list, as Apple Notes has it. Its tooltip is *Back*, the
/// name screen readers and tests know.
class BackToNotes extends StatelessWidget {
  const BackToNotes({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.chevron_left, size: 28),
        label: const Text('Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 4, right: 8)),
      ),
    );
  }
}
