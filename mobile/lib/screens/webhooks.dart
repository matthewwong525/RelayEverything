import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import 'back_to.dart';
import 'connect.dart' show ConnectScreen;
import 'folder.dart';

/// *Webhooks* on the phone, under *Advanced* on the Account page: a muted line that a person does not need it, the
/// webhooks by name as the server last answered, a link to the Relay Everything page to add or change one, and,
/// signed in, *Only to my own webhook* for health, places, the calendar and photos. The switch is off by default: then
/// everything the person turns on goes to Relay Everything.
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
            'For developers. Your own server gets a copy of your notes as they arrive. You do not need it to use '
            'Relay Everything.', style: muted)),
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
          if (relay.connected) ..._private(context),
        ])),
      ]);
    }));
  }

  /// *Only to my own webhook*: off, health, places, the calendar and photos go to Relay Everything with the notes; on,
  /// only to the person's own webhook, never both. On, it shows the webhook's host, *Send a test* and its last failure,
  /// or *Set your webhook again* when the phone lost it.
  List<Widget> _private(BuildContext context) {
    final brand = brandOf(context);
    final danger = Theme.of(context).colorScheme.error;
    final webhook = relay.settings.privateTo == SendPlace.webhook;
    return [
      Group(title: 'Health, places, calendar and photos', children: [
        SwitchListTile(
          title: const Text('Only to my own webhook'),
          subtitle: const Text('Straight from this phone. Relay Everything never gets them.'),
          value: webhook,
          onChanged: (on) => _pick(context, on ? SendPlace.webhook : SendPlace.server),
        ),
        if (webhook && relay.privateWebhookMissing) ListTile(
          title: Text('Set your webhook again', style: TextStyle(color: danger)),
          subtitle: const Text('This phone lost its address and secret. Your health, places, calendar and photos wait '
            'here until you do.'),
          trailing: const Icon(CupertinoIcons.chevron_forward),
          onTap: () => _setWebhook(context),
        ) else if (webhook) ...[
          ListTile(
            title: const Text('Webhook'),
            subtitle: Text(hostOf(relay.webhookAddress)),
            trailing: TextButton(onPressed: () => _test(context), style: quietButton(context), child: const Text('Send a test')),
          ),
          if (relay.webhookProblem case final problem?) ListTile(
            subtitle: Text(problemLine(problem, DateTime.now(), what: 'Health, places, calendar and photos'),
              style: TextStyle(color: danger)),
          ),
        ],
      ]),
      if (webhook) Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text('What already went to Relay Everything stays on your page. Your AI apps and your page show none of '
          'this from now on.', style: TextStyle(fontSize: 13, color: brand.muted)),
      ),
    ];
  }

  /// Off moves at once, with no question: it sends nothing new outside Relay Everything. On with no webhook kept first
  /// opens its setup; leaving it changes nothing.
  Future<void> _pick(BuildContext context, SendPlace place) async {
    if (place == SendPlace.webhook && relay.webhookAddress == null) return _setWebhook(context);
    await apply(context, relay.setPrivatePlace(place));
  }

  /// The webhook's setup, for private data only: its *Save* keeps the webhook, then private data goes there.
  Future<void> _setWebhook(BuildContext context) async {
    final saved = await Navigator.of(context).push(MaterialPageRoute<SendPlace>(
      builder: (_) => ConnectScreen(relay: relay, privateOnly: true)));
    if (saved == SendPlace.webhook && context.mounted) await apply(context, relay.setPrivatePlace(SendPlace.webhook));
  }

  Future<void> _test(BuildContext context) async {
    final answer = await relay.testWebhook(relay.webhookAddress ?? '', relay.webhookSecret ?? '');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(answer)));
  }
}
