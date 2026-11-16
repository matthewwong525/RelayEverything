import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import 'back_to.dart';
import 'folder.dart';

/// *Webhooks* on the phone, under *Advanced* on the Account page: a muted line that a person does not need it, the
/// webhooks by name as the server last answered, and a link to the Relay Everything page to add or change one. It holds
/// no choice of where data goes: signed in, everything goes to Relay Everything, which sends each webhook what the
/// person ticks for it.
class WebhooksPage extends StatelessWidget {
  const WebhooksPage({super.key, required this.relay, this.opener});

  final Relay relay;
  /// Opens the Relay Everything page; a test passes its own.
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    return Scaffold(body: ListenableBuilder(listenable: relay, builder: (context, _) {
      final names = relay.connections?.webhooks;
      return CustomScrollView(slivers: [
        SliverAppBar.large(leading: const BackTo('Account'), leadingWidth: BackTo.widthOf('Account'),
          title: const Text('Webhooks')),
        SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), sliver: SliverList.list(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(
            'For developers. Your own server gets a copy of your notes, and of what else you tick for it, as they '
            'arrive. You do not need it to use Relay Everything.', style: muted)),
          Group(children: [
            ...switch (names) {
              null => const <Widget>[],
              [] => [ListTile(title: Text('None yet', style: TextStyle(color: brand.muted)))],
              final names => [for (final name in names)
                ListTile(leading: Icon(CupertinoIcons.link, color: brand.accentText), title: Text(name))],
            },
            ListTile(
              title: Text('Add or change on your Relay Everything page',
                style: TextStyle(color: brand.accentText, fontWeight: FontWeight.w500)),
              trailing: Icon(CupertinoIcons.arrow_up_right_square, color: brand.muted),
              onTap: () => openRelayPage(context, relay, '#webhooks', opener: opener),
            ),
          ]),
        ])),
      ]);
    }));
  }
}
