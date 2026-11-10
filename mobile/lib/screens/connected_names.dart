import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../data/connection.dart' show defaultServer;
import '../relay.dart';
import 'back_to.dart';
import 'folder.dart';

/// What the phone's key may read of the person's connections: only names.
enum ConnectedKind {
  aiApps('AI apps', '#ai-apps', CupertinoIcons.sparkles),
  webhooks('Webhooks', '#webhooks', CupertinoIcons.link);

  const ConnectedKind(this.title, this.part, this.icon);

  final String title;
  /// The part of the Relay Everything page that changes them.
  final String part;
  final IconData icon;
}

/// *AI apps* or *Webhooks* on the phone, opened from the Account page: their names, as the server last answered, and
/// *Change on your Relay Everything page*. The phone's key reads no address, secret, device or send state.
class ConnectedNamesPage extends StatelessWidget {
  const ConnectedNamesPage({super.key, required this.relay, required this.kind, this.opener});

  final Relay relay;
  final ConnectedKind kind;
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Scaffold(body: ListenableBuilder(listenable: relay, builder: (context, _) {
      final connections = relay.connections;
      final names = connections == null ? null : kind == ConnectedKind.aiApps ? connections.aiApps : connections.webhooks;
      return CustomScrollView(slivers: [
        SliverAppBar.large(leading: const BackTo('Account'), leadingWidth: BackTo.widthOf('Account'), title: Text(kind.title)),
        SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), sliver: SliverList.list(children: [
          Group(children: switch (names) {
            null => [const ListTile(title: Text('See them on your page'))],
            [] => [const ListTile(title: Text('None yet'))],
            final names => [for (final name in names)
              ListTile(leading: Icon(kind.icon, color: brand.accentText), title: Text(name))],
          }),
          Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text(
            'This phone reads only their names. To add, change or remove one, use your Relay Everything page.',
            style: TextStyle(fontSize: 13, color: brand.muted))),
          Group(children: [ListTile(
            title: const Text('Change on your Relay Everything page'),
            trailing: const Icon(CupertinoIcons.arrow_up_right_square),
            onTap: () => _open(context),
          )]),
        ])),
      ]);
    }));
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final address = Uri.parse('${relay.server ?? defaultServer}/${kind.part}');
    if (!await (opener ?? openInBrowser)(address)) {
      messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
    }
  }
}
