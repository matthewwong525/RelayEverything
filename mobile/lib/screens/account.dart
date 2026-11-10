import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../data/connection.dart' show defaultServer;
import '../relay.dart';
import 'back_to.dart';
import 'connect.dart' show ConnectScreen, Scanner, ServerDialog;
import 'connected_names.dart';
import 'folder.dart';

/// Where this phone's account stands: signed in to a Relay Everything server, sending to the person's own webhook, or
/// signed out. A phone that keeps a key with sending off is signed out: its sign-in offers the key in one tap.
enum AccountState { signedIn, webhook, signedOut }

AccountState accountOf(Relay relay) {
  final settings = relay.settings;
  if (!settings.sending) return AccountState.signedOut;
  if (settings.place == SendPlace.webhook) return AccountState.webhook;
  return relay.connected && relay.server != null ? AccountState.signedIn : AccountState.signedOut;
}

/// *Account*, opened from the Account row in Settings. Signed in: the email and server, *AI apps* and *Webhooks* by
/// name, where health, places, the calendar and photos go, *Open your Relay Everything page*, the server to change,
/// and *Sign out*. With the person's own webhook: its address, *Send a test*, *Sign in to Relay Everything* and *Stop
/// sending*. Signing in there sends notes to Relay Everything and keeps the webhook for health, places, the calendar and
/// photos, then says how to get notes at the webhook too. Adding or removing an AI app or a webhook is on the web page.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.relay, this.opener, this.scanner});

  final Relay relay;
  /// Opens the Relay Everything page; a test passes its own.
  final Opener? opener;
  /// Opens the camera for *Scan a key* in the sign-in; Settings passes its own.
  final Scanner? scanner;

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
    final server = relay.server!;
    final names = relay.connections;
    final danger = Theme.of(context).colorScheme.error;
    return [
      Group(children: [ListTile(
        leading: const RelayMark(size: 32),
        title: Text(names?.email ?? hostOf(server), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: names?.email == null ? null : Text(hostOf(server)),
      )]),
      Group(title: 'Connections', children: [
        _connected(ConnectedKind.aiApps, names?.aiApps),
        _connected(ConnectedKind.webhooks, names?.webhooks),
      ]),
      ..._private(context),
      Group(children: [
        ListTile(
          title: const Text('Open your Relay Everything page'),
          subtitle: const Text('The notes from all your devices, with their recordings.'),
          trailing: const Icon(CupertinoIcons.arrow_up_right_square),
          onTap: () => _open(''),
        ),
        ListTile(
          title: const Text('Server'),
          subtitle: Text(server),
          trailing: const Icon(CupertinoIcons.pencil),
          onTap: () => _editServer(context),
        ),
      ]),
      Group(children: [ListTile(
        title: Text('Sign out', style: TextStyle(color: danger)),
        subtitle: const Text('Removes this phone\'s key and stops sending. Notes from this phone stay here.'),
        onTap: () => _signOut(context),
      )]),
    ];
  }

  /// *AI apps* or *Webhooks*: the names the server last gave, and a tap to their page, which links to the Relay
  /// Everything page, where the person adds or removes one.
  Widget _connected(ConnectedKind kind, List<String>? names) => FolderRow(
    icon: kind.icon, title: kind.title,
    line: switch (names) { null => 'See them on your page', [] => 'None yet', final names => names.join(', ') },
    count: names == null || names.isEmpty ? null : names.length,
    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConnectedNamesPage(relay: relay, kind: kind, opener: widget.opener))));

  /// *Health, places, calendar and photos*: to Relay Everything with the notes, or only to the person's own webhook. With
  /// the webhook picked: its host, *Send a test* and its last failure, or *Set your webhook again* when the phone lost
  /// it. The picked row's check is its only mark: no filled button.
  List<Widget> _private(BuildContext context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;
    final webhook = relay.settings.privateTo == SendPlace.webhook;
    return [
      Group(title: 'Health, places, calendar and photos', children: [
        RadioGroup<SendPlace>(
          groupValue: relay.settings.privateTo,
          onChanged: (place) { if (place != null) _pickPrivate(context, place); },
          child: const Column(children: [
            RadioListTile(value: SendPlace.server, title: Text('Relay Everything'),
              subtitle: Text('Your AI and your page can see them.')),
            RadioListTile(value: SendPlace.webhook, title: Text('Only my own webhook'),
              subtitle: Text('Straight from this phone. Relay Everything never gets them.')),
          ]),
        ),
        if (webhook && relay.privateWebhookMissing) ListTile(
          title: Text('Set your webhook again', style: TextStyle(color: danger)),
          subtitle: const Text('This phone lost its address and secret. Your health, places, calendar and photos wait '
            'here until you do.'),
          trailing: const Icon(CupertinoIcons.chevron_forward),
          onTap: () => _setPrivateWebhook(context),
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
          'this from now on.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    ];
  }

  /// *Relay Everything* moves at once, with no question: it sends nothing new outside the person's server. *Only my own
  /// webhook* with no webhook kept first opens its setup; leaving it changes nothing.
  Future<void> _pickPrivate(BuildContext context, SendPlace place) async {
    if (place == SendPlace.webhook && relay.webhookAddress == null) return _setPrivateWebhook(context);
    await apply(context, relay.setPrivatePlace(place));
  }

  /// The webhook's setup, for private data only: its *Save* keeps the webhook, then private data goes there.
  Future<void> _setPrivateWebhook(BuildContext context) async {
    final saved = await Navigator.of(context).push(MaterialPageRoute<SendPlace>(
      builder: (_) => ConnectScreen(relay: relay, privateOnly: true)));
    if (saved == SendPlace.webhook && context.mounted) await apply(context, relay.setPrivatePlace(SendPlace.webhook));
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
    if (!await choosePlace(context, relay, widget.scanner, keepWebhook: true)) return;
    unawaited(relay.refreshConnections());
    messenger.showSnackBar(const SnackBar(content: Text('Signed in. To get your notes at your webhook too, add it under '
      'Webhooks on your Relay Everything page.')));
  }

  /// [part] of the person's Relay Everything page, such as `#webhooks`, in the phone's browser.
  Future<void> _open(String part) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await (widget.opener ?? openInBrowser)(Uri.parse('${relay.server ?? defaultServer}/apps/relay/$part'))) {
      messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
    }
  }

  Future<void> _test(BuildContext context) async {
    final answer = await relay.testWebhook(relay.webhookAddress ?? '', relay.webhookSecret ?? '');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(answer)));
  }

  Future<void> _editServer(BuildContext context) async {
    final address = await showDialog<String>(context: context, builder: (context) => ServerDialog(server: relay.server));
    if (address != null && context.mounted) await apply(context, relay.setServer(address));
  }

  /// Asks first, then forgets the key and stops sending, and goes back to Settings, which says *Sign in*.
  Future<void> _signOut(BuildContext context) async {
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text('Sending stops and this phone forgets its key. Notes from this phone stay here. Notes from your '
        'other phones and email leave this phone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
      ],
    ));
    if (sure != true) return;
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
