import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'round_button.dart';

/// The width an app bar gives [BackToNotes].
const backToNotesWidth = 64.0;

/// The round *‹* at the top left of each page the app opens, as Apple Notes has it, in place of Material's arrow. Its
/// tooltip is *Back*, the name screen readers and tests know.
class BackToNotes extends StatelessWidget {
  const BackToNotes({super.key});

  @override
  Widget build(BuildContext context) => Center(child: RoundIconButton(icon: CupertinoIcons.chevron_back, tooltip: 'Back',
    onPressed: () => Navigator.of(context).maybePop()));
}
