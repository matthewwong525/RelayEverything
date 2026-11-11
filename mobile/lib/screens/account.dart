import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import 'back_to.dart';
import 'days.dart' show shortDay;
import 'folder.dart';
import 'timeline.dart' show openPage;
import 'webhooks.dart';

/// Where this phone's account stands: signed in to a Relay Everything server, sending to the person's own webhook, or
/// signed out. A phone that keeps a key with sending off is signed out: its sign-in offers the key in one tap.
enum AccountState { signedIn, webhook, signedOut }

AccountState accountOf(Relay relay) {
  final settings = relay.settings;
  if (!settings.sending) return AccountState.signedOut;
  if (settings.place == SendPlace.webhook) return AccountState.webhook;
  return relay.connected && relay.server != null ? AccountState.signedIn : AccountState.signedOut;
}

/// The day a device first signed in, such as *Since Oct 14*, with the year when it is not this year.
String sinceLine(DateTime? since, DateTime now) => since == null ? 'Signed in' : 'Since ${shortDay(since, now)}';

/// Asks before a *Sign out*; true on a yes.
Future<bool> confirmSignOut(BuildContext context, {required String title, required String body}) async =>
  await showDialog<bool>(context: context, builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(body),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
    ],
  )) == true;

/// *Account*, opened from the account card in Settings. Signed in, in this order: the email, *Signed in* and a quiet
/// *Sign out*; *Phones*, this one marked *This phone* and each other with *Sign out*; *Advanced*, with *Webhooks*; and
/// *Delete my account*, which opens the Relay Everything page. Computers show in *Connect your AI*. With the person's
/// own webhook and no account: its address, *Send a test*, *Sign in to Relay Everything* and *Stop sending*. Signing
/// in there sends notes to Relay Everything and keeps the webhook for health, places, the calendar and photos.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.relay, this.opener});

  final Relay relay;
  /// Opens the Relay Everything page; a test passes its own.
  final Opener? opener;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Relay get relay => widget.relay;

  @override
  void initState() {
    super.initState();
    // It asks only while the phone sends to a Relay Everything server.
    relay.refreshConnections();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) => CustomScrollView(slivers: [
          SliverAppBar.large(leading: const BackTo('Settings'), leadingWidth: BackTo.widthOf('Settings'),
            title: const Text('Account')),
          SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), sliver: SliverList.list(children: switch (accountOf(relay)) {
            AccountState.signedIn => _server(context),
            AccountState.webhook => _webhook(context),
            // Signed out while the page is open: nothing to show until Settings is back.
            AccountState.signedOut => const <Widget>[],
          })),
        ]),
      ),
    );
  }

  List<Widget> _server(BuildContext context) {
    final brand = brandOf(context);
    final connections = relay.connections;
    final danger = Theme.of(context).colorScheme.error;
    final now = DateTime.now();
    final webhooks = connections?.webhooks;
    return [
      Group(children: [ListTile(
        leading: const RelayMark(size: 32),
        title: Text(connections?.email ?? hostOf(relay.server), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Signed in'),
        trailing: TextButton(onPressed: () => _signOut(context), style: quietButton(context), child: const Text('Sign out')),
      )]),
      if (connections case final connections? when connections.phones.isNotEmpty) Group(title: 'Phones', children: [
        for (final phone in connections.phones) ListTile(
          leading: Icon(CupertinoIcons.device_phone_portrait, color: brand.accentText),
          title: Text(phone.name),
          subtitle: Text(phone.id == connections.thisDevice ? 'This phone' : sinceLine(phone.since, now)),
          trailing: phone.id == connections.thisDevice ? null
            : TextButton(onPressed: () => _signOutPhone(context, phone), style: quietButton(context), child: const Text('Sign out')),
        ),
      ]),
      Group(title: 'Advanced', children: [
        FolderRow(icon: CupertinoIcons.link, title: 'Webhooks', line: 'Send a copy to your own server',
          count: webhooks == null || webhooks.isEmpty ? null : webhooks.length,
          onTap: () => openPage(context, WebhooksPage(relay: relay, opener: widget.opener))),
      ]),
      Group(children: [ListTile(
        title: Text('Delete my account', style: TextStyle(color: danger)),
        subtitle: const Text('On your Relay Everything page'),
        trailing: Icon(CupertinoIcons.arrow_up_right_square, color: brand.muted),
        onTap: () => openRelayPage(context, relay, '#account', opener: widget.opener),
      )]),
    ];
  }

  /// Asks first, then signs out another of the person's phones: it stops at its next request, and the others go on.
  Future<void> _signOutPhone(BuildContext context, ConnectedDevice phone) async {
    if (!await confirmSignOut(context, title: 'Sign out ${phone.name}?',
      body: 'It stops sending at its next request. Its notes stay on it. Sign in on it again to send from it.')) {
      return;
    }
    if (!context.mounted) return;
    await apply(context, relay.signOutPhone(phone.id));
  }

  List<Widget> _webhook(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return [
      Group(children: [
        ListTile(
          leading: Icon(CupertinoIcons.link, color: brandOf(context).accentText),
          title: const Text('My own webhook', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(relay.webhookAddress ?? ''),
          trailing: TextButton(onPressed: () => _test(context), style: quietButton(context), child: const Text('Send a test')),
        ),
        if (relay.webhookProblem case final problem?) ListTile(
          subtitle: Text(problemLine(problem, DateTime.now()), style: TextStyle(color: danger)),
        ),
      ]),
      Group(children: [ListTile(
        title: const Text('Sign in to Relay Everything'),
        subtitle: const Text('Sync your notes with your page, your AI and your other phones. Health, places, calendar and '
          'photos still go only to your webhook.'),
        trailing: const Icon(CupertinoIcons.chevron_forward),
        onTap: () => _signIn(context),
      )]),
      Group(children: [ListTile(
        title: Text('Stop sending', style: TextStyle(color: danger)),
        subtitle: const Text('New notes stay on this phone. The phone keeps your webhook\'s address and secret.'),
        onTap: () => _stopSending(context),
      )]),
    ];
  }

  /// The sign-in, with the webhook kept for private data. Once signed in, the page shows the account, and a message says
  /// the webhook gets no notes from the phone until the person adds it on their page.
  Future<void> _signIn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await choosePlace(context, relay, keepWebhook: true)) return;
    unawaited(relay.refreshConnections());
    messenger.showSnackBar(const SnackBar(content: Text('Signed in. To get your notes at your webhook too, add it under '
      'Webhooks on your Relay Everything page.')));
  }

  Future<void> _test(BuildContext context) async {
    final answer = await relay.testWebhook(relay.webhookAddress ?? '', relay.webhookSecret ?? '');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(answer)));
  }

  /// Asks first, then forgets the key and stops sending, and goes back to Settings, which says *Sign in*.
  Future<void> _signOut(BuildContext context) async {
    if (!await confirmSignOut(context, title: 'Sign out?',
      body: 'Sending stops and this phone forgets its key. Notes from this phone stay here. Notes from your other phones '
        'and email leave this phone.')) {
      return;
    }
    await relay.disconnect();
    if (context.mounted) Navigator.of(context).maybePop();
  }

  /// Asks first, then stops sending to the webhook. The webhook stays kept, so sending there again needs no new secret.
  Future<void> _stopSending(BuildContext context) async {
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Stop sending?'),
      content: const Text('New notes stay on this phone. Notes already at your webhook stay there. '
        'Health, the calendar, location and photos stop.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop sending')),
      ],
    ));
    if (sure != true) return;
    await relay.stopSending();
    if (context.mounted) Navigator.of(context).maybePop();
  }
}
