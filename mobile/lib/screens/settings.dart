import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../brand.dart';
import '../relay.dart';
import '../voice/model.dart' show megabytes;
import 'back_to.dart';
import 'folder.dart' show Group, apply;

/// What is about this phone alone: *Appearance*, *Pin notes to where I am*, the speech model, and at the bottom the
/// app's version and build. Sending and each kind of phone data have their own folder on Home.
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
            Group(title: 'Appearance', children: [_AppearanceRow(relay: relay)]),
            Group(title: 'Notes', children: [
              SwitchListTile(
                title: const Text('Pin notes to where I am'),
                subtitle: const Text('Each typed note keeps where you were.'),
                value: relay.settings.pinNotes,
                onChanged: (on) => apply(context, relay.setPinNotes(on)),
              ),
            ]),
            Group(title: 'Voice notes', children: [_VoiceRow(relay: relay)]),
            const _Version(),
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

/// *System*, *Light* and *Dark*. The picked one has the quiet accent fill, so *New note* stays the one filled accent.
class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow({required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<Appearance>(
        segments: const [
          ButtonSegment(value: Appearance.system, label: Text('System')),
          ButtonSegment(value: Appearance.light, label: Text('Light')),
          ButtonSegment(value: Appearance.dark, label: Text('Dark')),
        ],
        selected: {relay.settings.appearance},
        showSelectedIcon: false,
        onSelectionChanged: (picked) => relay.setAppearance(picked.single),
        style: SegmentedButton.styleFrom(selectedBackgroundColor: brand.accentSoft, selectedForegroundColor: brand.ink,
          foregroundColor: brand.ink, side: BorderSide(color: brand.line)),
      ),
    );
  }
}

/// *Relay Everything 1.4.0 (91)*: the version and build, so the person knows which build they have.
class _Version extends StatefulWidget {
  const _Version();

  @override
  State<_Version> createState() => _VersionState();
}

class _VersionState extends State<_Version> {
  late final _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, info) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Text(switch (info.data) { final info? => 'Relay Everything ${info.version} (${info.buildNumber})', null => '' },
          textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: brandOf(context).muted)),
      ),
    );
  }
}
