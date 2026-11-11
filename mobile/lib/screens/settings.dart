import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../brand.dart';
import '../relay.dart';
import '../voice/model.dart' show megabytes;
import 'account.dart';
import 'back_to.dart';
import 'folder.dart' show Group, Opener, choosePlace, hostOf;
import 'timeline.dart' show openPage;

/// The rows of Settings, in order, on the phone and in the browser: one list, so a row added later shows on both, or is
/// marked phone-only on purpose. The browser hears no voice and has no version to show.
enum SettingsRow {
  account('Account'),
  appearance('Appearance'),
  voice('Voice notes', phoneOnly: true),
  version('Version', phoneOnly: true);

  const SettingsRow(this.title, {this.phoneOnly = false});

  final String title;
  final bool phoneOnly;

  /// The rows the phone, or with [web] the browser, shows.
  static List<SettingsRow> on({required bool web}) => [for (final row in values) if (!web || !row.phoneOnly) row];
}

/// The account card first, as the Apple Account card in iPhone Settings, then *Appearance*, and what is about this
/// phone alone: the speech model, and at the bottom the app's version and build, as
/// [SettingsRow] lists them. Each kind of phone data has its own folder on Home.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.relay, this.opener});

  final Relay relay;
  /// Opens the Relay Everything page; a test passes its own.
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) => CustomScrollView(slivers: [
          SliverAppBar.large(leading: const BackTo('Home'), leadingWidth: BackTo.widthOf('Home'), title: const Text('Settings')),
          SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), sliver: SliverList.list(children: [
            for (final row in SettingsRow.on(web: relay.web)) switch (row) {
              SettingsRow.account => AccountCard(relay: relay, opener: opener),
              SettingsRow.appearance => Group(title: row.title, children: [_AppearanceRow(relay: relay)]),
              SettingsRow.voice => Group(title: row.title, children: [_VoiceRow(relay: relay)]),
              SettingsRow.version => const _Version(),
            },
          ])),
        ]),
      ),
    );
  }
}

/// The account, in its own card: signed in, the Relay Everything mark, the email and *Signed in*, and nothing more;
/// with the person's own webhook, *My own webhook* and its address; else *Sign in to Relay Everything*. Signed out, a
/// tap opens the sign-in; else it opens the Account page.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.relay, this.opener});

  final Relay relay;
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final state = accountOf(relay);
    final email = relay.connections?.email;
    final (String title, String line) = switch (state) {
      AccountState.signedIn => (email ?? hostOf(relay.server), 'Signed in'),
      AccountState.webhook => ('My own webhook', hostOf(relay.webhookAddress)),
      AccountState.signedOut => ('Sign in to Relay Everything', 'Your notes stay on this phone until you sign in.'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: const ValueKey('account'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: state == AccountState.webhook
            ? Icon(CupertinoIcons.link, size: 32, color: brand.accentText)
            : const RelayMark(size: 40),
          title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: brand.ink)),
          subtitle: Text(line, style: TextStyle(fontSize: 13, color: brand.muted)),
          trailing: Icon(CupertinoIcons.chevron_forward, color: brand.muted),
          onTap: () => state == AccountState.signedOut
            ? choosePlace(context, relay)
            : openPage(context, AccountPage(relay: relay, opener: opener)),
        ),
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
