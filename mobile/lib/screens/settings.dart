import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import '../voice/model.dart' show megabytes;
import 'back_to.dart';
import 'folder.dart' show Group, apply;

/// What is about notes on this phone alone: *Pin notes to where I am* and the speech model. Sending and each kind of
/// phone data have their own folder on Home.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) => CustomScrollView(slivers: [
          SliverAppBar.large(leading: const BackTo('Home'), leadingWidth: BackTo.widthOf('Home'), title: const Text('Settings')),
          SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), sliver: SliverList.list(children: [
            Group(title: 'Notes', children: [
              SwitchListTile(
                title: const Text('Pin notes to where I am'),
                subtitle: const Text('Each typed note keeps where you were.'),
                value: relay.settings.pinNotes,
                onChanged: (on) => apply(context, relay.setPinNotes(on)),
              ),
            ]),
            Group(title: 'Voice notes', children: [_VoiceRow(relay: relay)]),
          ])),
        ]),
      ),
    );
  }
}

/// The speech model voice notes use: where it is, its size, and *Remove* to free the space. The voice never leaves
/// the phone.
class _VoiceRow extends StatelessWidget {
  const _VoiceRow({required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final size = megabytes(relay.modelBytes);
    final state = switch (relay.speechModel) {
      ModelState.ready => 'On this phone, $size. Your voice never leaves it.',
      ModelState.downloading => 'Getting it… ${(relay.modelProgress * 100).floor()}%',
      ModelState.failed => 'It did not download. Hold New note to try again.',
      _ => 'Not on this phone. Your first voice note asks to get it, $size.',
    };
    return ListTile(
      title: const Text('Speech model'),
      subtitle: Text(state),
      trailing: relay.speechModel == ModelState.ready
        ? TextButton(onPressed: relay.removeSpeechModel, style: quietButton(context), child: const Text('Remove'))
        : null,
    );
  }
}
