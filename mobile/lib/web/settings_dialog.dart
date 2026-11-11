import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import '../screens/account.dart' show confirmSignOut, sinceLine;
import '../screens/folder.dart' show FolderRow, Group, Opener;
import '../screens/settings.dart' show SettingsRow;
import 'devices_page.dart';
import 'settings_parts.dart';
import 'space.dart';
import 'webhooks_page.dart';

/// The pages of Settings in the browser. Its list shows those of [SettingsRow], the same rows as the phone's
/// Settings; *API keys* and *Webhooks* open from *Advanced* on Account.
enum SettingsPage {
  account('Account', 'account', CupertinoIcons.person_crop_circle),
  appearance('Appearance', 'appearance', CupertinoIcons.circle_lefthalf_fill),
  apiKeys('API keys', 'api-keys', CupertinoIcons.chevron_left_slash_chevron_right),
  webhooks('Webhooks', 'webhooks', CupertinoIcons.link);

  const SettingsPage(this.title, this.part, this.icon);

  final String title;
  /// The page's part of the address, such as `#webhooks` in `/#webhooks`: the phone's *Webhooks* opens Settings on
  /// that page.
  final String part;
  final IconData icon;

  /// The pages Settings' list shows, in the order of [SettingsRow].
  static List<SettingsPage> get listed => [
    for (final row in SettingsRow.on(web: true)) switch (row) {
      SettingsRow.account => account,
      SettingsRow.appearance => appearance,
      // The browser shows no phone-only row.
      SettingsRow.voice || SettingsRow.version => throw StateError('${row.name} is phone-only'),
    },
  ];

  /// The list's row a page sits under: *API keys* and *Webhooks* under Account.
  SettingsPage get inList => this == apiKeys || this == webhooks ? account : this;

  /// The page an address's part names, such as `webhooks` or `/api-keys`; null for any other part. The old page
  /// `devices` opens Account, which lists the phones.
  static SettingsPage? ofPart(String part) {
    final name = part.startsWith('/') ? part.substring(1) : part;
    if (name == 'devices') return account;
    return values.where((page) => page.part == name).firstOrNull;
  }
}

/// Below this width Settings fills the window, with its list first.
const _narrow = 700.0;

/// Opens Settings over the notes: its pages down the left, the open page on the right, and a close button. In a window
/// under 700 px it fills the window and shows the list first. It returns when it closes; the open note stays as it was.
Future<void> showSettingsDialog(BuildContext context, {required Relay relay, required SpaceClient client, Opener? opener,
    SettingsPage first = SettingsPage.account}) =>
  showDialog<void>(context: context, builder: (context) {
    final narrow = MediaQuery.sizeOf(context).width < _narrow;
    final view = SettingsView(relay: relay, client: client, opener: opener, first: first, narrow: narrow);
    if (narrow) return Dialog.fullscreen(child: view);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(width: 880, height: 620, child: view),
    );
  });

/// Settings' list and its open page, with its own messenger so a message shows over the dialog, not under it.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.relay, required this.client, this.opener,
    this.first = SettingsPage.account, this.narrow = false});

  final Relay relay;
  final SpaceClient client;
  final Opener? opener;
  final SettingsPage first;
  /// The list alone, then one page at a time with a way back to the list.
  final bool narrow;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  /// Null in a narrow window while the list shows.
  late SettingsPage? _page = widget.narrow && widget.first == SettingsPage.account ? null : widget.first;

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final page = _page;
    final Widget body;
    if (widget.narrow) {
      body = page == null ? _list(context) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(8, 8, 0, 0), child: Tooltip(message: 'Back', child: TextButton.icon(
          onPressed: () => setState(() => _page = null),
          icon: const Icon(CupertinoIcons.chevron_back), label: const Text('Settings')))),
        Expanded(child: _pageOf(page)),
      ]);
    } else {
      body = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 220, child: _list(context)),
        VerticalDivider(width: 1, color: brand.line),
        Expanded(child: _pageOf(page ?? SettingsPage.account)),
      ]);
    }
    return ScaffoldMessenger(child: Scaffold(
      backgroundColor: brand.paper,
      body: SafeArea(child: Stack(children: [
        Positioned.fill(child: body),
        Positioned(top: 12, right: 12, child: IconButton(
          style: IconButton.styleFrom(backgroundColor: brand.card),
          icon: const Icon(CupertinoIcons.xmark, size: 18), tooltip: 'Close', onPressed: _close)),
      ])),
    ));
  }

  Widget _list(BuildContext context) {
    final brand = brandOf(context);
    return ListView(padding: const EdgeInsets.all(14), children: [
      Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 12), child: Text('Settings',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
      for (final item in SettingsPage.listed) Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: ListTile(
          key: ValueKey('settings-${item.name}'),
          dense: true,
          selected: !widget.narrow && item == (_page ?? SettingsPage.account).inList,
          selectedTileColor: brand.accentSoft,
          selectedColor: brand.accentText,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(item.icon, size: 20),
          title: Text(item.title, style: const TextStyle(fontSize: 15)),
          trailing: widget.narrow ? const Icon(CupertinoIcons.chevron_forward, size: 18) : null,
          onTap: () => setState(() => _page = item),
        ),
      ),
    ]);
  }

  void _account() => setState(() => _page = SettingsPage.account);

  Widget _pageOf(SettingsPage page) => KeyedSubtree(key: ValueKey(page), child: switch (page) {
    SettingsPage.account => _AccountPage(relay: widget.relay, client: widget.client, close: _close,
      open: (page) => setState(() => _page = page)),
    SettingsPage.apiKeys => ApiKeysPage(client: widget.client, opener: widget.opener, back: _account),
    SettingsPage.webhooks => WebhooksPage(client: widget.client, back: _account),
    SettingsPage.appearance => _AppearancePage(relay: widget.relay),
  });
}

bool _same(String one, String other) => one.trim().toLowerCase() == other.trim().toLowerCase();

/// *Account*, as on the phone: who is signed in with *Sign out*; *Phones*, each with *Sign out* after a confirm;
/// *Advanced*, with *API keys* and *Webhooks*; and *Delete my account*, which needs the email typed again. Computers
/// show in *Connect your AI*.
class _AccountPage extends StatelessWidget {
  const _AccountPage({required this.relay, required this.client, required this.close, required this.open});

  final Relay relay;
  final SpaceClient client;
  final VoidCallback close;
  /// Opens a page of *Advanced*.
  final ValueChanged<SettingsPage> open;

  Future<(String, Connections)> _load() async {
    final email = '${(await client.get('account'))['email'] ?? ''}';
    return (email, Connections.fromJson(await client.get('connections')));
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final danger = brand.danger;
    final now = DateTime.now();
    return SettingsBody(title: 'Account', children: [SpaceView<(String, Connections)>(
      what: 'Your account', load: _load,
      builder: (context, value, act) {
        final (email, connections) = value;
        final webhooks = connections.webhooks.length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Group(children: [ListTile(
            leading: const RelayMark(size: 32),
            title: Text(email, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Signed in'),
            trailing: TextButton(onPressed: _signOut, style: quietButton(context), child: const Text('Sign out')),
          )]),
          if (connections.phones.isNotEmpty) Group(title: 'Phones', children: [
            for (final phone in connections.phones) ListTile(
              leading: Icon(CupertinoIcons.device_phone_portrait, color: brand.accentText),
              title: Text(phone.name),
              subtitle: Text(sinceLine(phone.since, now)),
              trailing: TextButton(onPressed: () => _signOutPhone(context, phone, act), style: quietButton(context),
                child: const Text('Sign out')),
            ),
          ]),
          Group(title: 'Advanced', children: [
            FolderRow(icon: SettingsPage.apiKeys.icon, title: 'API keys', line: 'For your own scripts',
              onTap: () => open(SettingsPage.apiKeys)),
            FolderRow(icon: SettingsPage.webhooks.icon, title: 'Webhooks', line: 'Send a copy to your own server',
              count: webhooks == 0 ? null : webhooks, onTap: () => open(SettingsPage.webhooks)),
          ]),
          Group(children: [ListTile(
            title: Text('Delete my account', style: TextStyle(color: danger)),
            subtitle: const Text('Removes your notes, recordings, photos, health, places, chats, devices, webhooks and AI apps.'),
            onTap: () => _delete(context, email),
          )]),
        ]);
      })]);
  }

  /// Asks first, then signs out one phone: it stops at its next request, and the others go on.
  Future<void> _signOutPhone(BuildContext context, ConnectedDevice phone, Act act) async {
    if (!await confirmSignOut(context, title: 'Sign out ${phone.name}?',
      body: 'It stops sending at its next request. Its notes stay on it. Sign in on it again to send from it.')) {
      return;
    }
    await act(() => client.post('devices/off', {'id': phone.id}));
  }

  /// Closes Settings first: signing out shows the sign-in in place of the notes.
  Future<void> _signOut() async {
    close();
    await relay.disconnect();
  }

  Future<void> _delete(BuildContext context, String email) async {
    final deleted = await showDialog<bool>(context: context, builder: (_) => _DeleteDialog(client: client, email: email));
    if (deleted != true) return;
    close();
    await relay.disconnect();
  }
}

/// *Delete your account?*: the email typed again turns on *Delete everything*. Closes with true once deleted.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.client, required this.email});

  final SpaceClient client;
  final String email;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _typed = TextEditingController();
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() { _busy = true; _problem = null; });
    try {
      await widget.client.post('account-delete', {'email': _typed.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } on SpaceRefused catch (refused) {
      if (mounted) setState(() { _problem = refused.message; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SizedBox(width: 440, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        spacing: 12, children: [
          const Text('This removes your notes, recordings, photos, health, places, chats, devices, webhooks and connected AI '
            'apps. You can not undo this.'),
          TextField(controller: _typed, autocorrect: false, keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Type your email, ${widget.email}, to confirm',
              border: const OutlineInputBorder())),
          if (_problem case final problem?) Problem(problem),
        ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: brand.danger, foregroundColor: brand.onDanger),
          onPressed: _busy || !_same(_typed.text, widget.email) ? null : _delete,
          child: const Text('Delete everything')),
      ],
    );
  }
}

/// *Appearance*: System, Light or Dark.
class _AppearancePage extends StatelessWidget {
  const _AppearancePage({required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    return SettingsBody(title: 'Appearance', children: [
      const SizedBox(height: 8),
      ListenableBuilder(listenable: relay, builder: (context, _) => Align(alignment: Alignment.centerLeft,
        child: SegmentedButton<Appearance>(
          segments: const [
            ButtonSegment(value: Appearance.system, label: Text('System')),
            ButtonSegment(value: Appearance.light, label: Text('Light')),
            ButtonSegment(value: Appearance.dark, label: Text('Dark')),
          ],
          selected: {relay.settings.appearance},
          showSelectedIcon: false,
          onSelectionChanged: (picked) => relay.setAppearance(picked.single),
        ))),
    ]);
  }
}
