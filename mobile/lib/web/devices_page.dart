import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../screens/folder.dart' show Group, Opener, openInBrowser;
import 'settings_parts.dart';
import 'space.dart';

/// The server's word for an API key's reach. A phone signs in from the app, and a computer connects itself with
/// `/relay:connect`: only an API key is made here.
const apiReach = 'api';

/// The name an API key gets when the person types none.
const apiKeyName = 'Script';

/// *API keys*, under *Advanced* on the Account page: each API key, with *Turn off* while it works, and *Add an API
/// key*, which shows the new key once. Phones show on Account and computers in *Connect your AI*.
class ApiKeysPage extends StatelessWidget {
  const ApiKeysPage({super.key, required this.client, this.opener, this.back});

  final SpaceClient client;
  final Opener? opener;
  /// *‹ Account*, back to the page that opened it.
  final VoidCallback? back;

  Future<List<Map<String, dynamic>>> _load() async =>
    [for (final device in listOf(await client.get('devices'), 'devices')) if (device['reaches'] == apiReach) device];

  @override
  Widget build(BuildContext context) {
    return SettingsBody(title: 'API keys', back: back, line: 'For your own scripts. One key can serve many scripts.',
      children: [
        SpaceView<List<Map<String, dynamic>>>(what: 'API keys', load: _load, builder: (context, keys, act) => Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (keys.isEmpty) const Note('No API keys yet.')
            else Group(children: [for (final key in keys) _KeyRow(device: key, client: client, act: act)]),
            const SizedBox(height: 16),
            FilledButton.icon(
              // The list reads again once the key is made, so the new key shows however the dialog closes.
              onPressed: () => showDialog<bool>(context: context,
                builder: (_) => AddApiKeyDialog(client: client, opener: opener, onMade: act)),
              icon: const Icon(CupertinoIcons.add), label: const Text('Add an API key')),
          ])),
      ]);
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.device, required this.client, required this.act});

  final Map<String, dynamic> device;
  final SpaceClient client;
  final Act act;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final name = '${device['name']}';
    final on = device['revokedAt'] == null;
    final added = device['createdAt'] is int ? ' · added ${whenOf(device['createdAt'] as int)}' : '';
    return ListTile(
      leading: Icon(CupertinoIcons.chevron_left_slash_chevron_right, color: on ? brand.accentText : brand.muted),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('Reads and adds notes$added'),
      trailing: on
        ? TextButton(onPressed: () => _turnOff(context, name), style: quietButton(context), child: const Text('Turn off'))
        : const BrandTag('Off'),
    );
  }

  Future<void> _turnOff(BuildContext context, String name) async {
    final sure = await confirm(context, title: 'Turn off $name?', action: 'Turn off',
      body: 'Its key stops working at once. What it sent stays. To use the script again, add a new key.');
    if (!sure) return;
    await act(() => client.post('devices/off', {'id': device['id']}));
  }
}

/// *Add an API key*: a name, then the new key's steps. The key shows only in this dialog: closing it forgets the key,
/// and the page never shows it again. Closes with true once a key was made; [onMade] runs as the key is made.
class AddApiKeyDialog extends StatefulWidget {
  const AddApiKeyDialog({super.key, required this.client, this.opener, this.onMade});

  final SpaceClient client;
  final Opener? opener;
  final Future<void> Function()? onMade;

  @override
  State<AddApiKeyDialog> createState() => _AddApiKeyDialogState();
}

class _AddApiKeyDialogState extends State<AddApiKeyDialog> {
  final _name = TextEditingController();
  Map<String, dynamic>? _made;
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    setState(() { _busy = true; _problem = null; });
    try {
      final name = _name.text.trim().isEmpty ? apiKeyName : _name.text.trim();
      final made = await widget.client.post('devices', {'name': name, 'reaches': apiReach});
      if (mounted) setState(() => _made = made);
      unawaited(widget.onMade?.call());
    } on SpaceRefused catch (refused) {
      if (mounted) setState(() => _problem = refused.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final made = _made;
    return AlertDialog(
      title: Text(made == null ? 'Add an API key' : 'Use ${made['name']}'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: made == null ? _form() : _steps(made)))),
      actions: made == null ? [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _make, child: const Text('Make the key')),
      ] : [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done'))],
    );
  }

  List<Widget> _form() => [
    const Text('An API key lets your own script read and add notes. You can turn each key off alone.'),
    const SizedBox(height: 16),
    TextField(controller: _name, maxLength: 60,
      decoration: const InputDecoration(labelText: 'Name', hintText: apiKeyName, border: OutlineInputBorder())),
    if (_problem case final problem?) Problem(problem),
  ];

  List<Widget> _steps(Map<String, dynamic> made) {
    final key = '${made['key']}';
    final open = widget.opener ?? openInBrowser;
    return [
      const Note('Relay Everything shows this key once. Do these steps before you close this window.'),
      const Text("1. Copy the key into your script or service's secret store. Never put it in a file you share:"),
      CopyField(text: key, label: 'The key', button: 'Copy the key'),
      const Text('2. Send it as a header. This call names the key and reads no data:'),
      CopyField(text: 'curl -H "Authorization: Bearer $key" ${made['api'] ?? '<your-relay-server>/v1'}/me',
        label: 'The example', button: 'Copy the example'),
      const Text('3. The key reads and adds notes. It can not change or delete them.'),
      Align(alignment: Alignment.centerLeft,
        child: TextButton(onPressed: () => open(Uri.parse(apiDocs)), child: const Text("Read the web API's routes"))),
    ];
  }
}
