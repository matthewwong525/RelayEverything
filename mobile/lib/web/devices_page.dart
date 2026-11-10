import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../brand.dart';
import '../screens/folder.dart' show Group, Opener, openInBrowser;
import 'settings_parts.dart';
import 'space.dart';

/// What a new device may do: a phone, Claude Code or a script with an API key. [reaches] is the server's word.
enum DeviceKind {
  phone('Phone', 'Phone', 'phone', CupertinoIcons.device_phone_portrait),
  claude('Claude Code', 'Laptop', 'chats', CupertinoIcons.device_laptop),
  api('API key', 'Script', 'api', CupertinoIcons.chevron_left_slash_chevron_right);

  const DeviceKind(this.label, this.name, this.reaches, this.icon);

  final String label;
  /// The name a device gets when the person types none.
  final String name;
  final String reaches;
  final IconData icon;

  static DeviceKind? of(Object? reaches) => values.where((kind) => kind.reaches == reaches).firstOrNull;
}

const _reachLines = {'phone': 'Notes, health, places, calendar and photos', 'chats': 'Chats', 'api': 'API: reads and adds notes'};

/// *Devices*: each device's own key, with *Turn off* while it works, and *Add a device*, which shows the new key once.
/// The server leaves out the keyless ways in, *Email* and the page's own *Web*.
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, required this.client, this.opener});

  final SpaceClient client;
  final Opener? opener;

  Future<List<Map<String, dynamic>>> _load() async =>
    // Only the kinds a key has: a keyless device has nothing to turn off.
    [for (final device in listOf(await client.get('devices'), 'devices')) if (DeviceKind.of(device['reaches']) != null) device];

  @override
  Widget build(BuildContext context) {
    return SettingsBody(title: 'Devices', line: 'Each phone and Claude Code computer sends with its own key.', children: [
      SpaceView<List<Map<String, dynamic>>>(what: 'Devices', load: _load, builder: (context, devices, act) => Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (devices.isEmpty) const Note('No devices yet. Add a phone or Claude Code to start sending.')
          else Group(children: [for (final device in devices) _DeviceRow(device: device, client: client, act: act)]),
          const SizedBox(height: 16),
          FilledButton.icon(
            // The list reads again once the key is made, so the new device shows however the dialog closes.
            onPressed: () => showDialog<bool>(context: context,
              builder: (_) => AddDeviceDialog(client: client, opener: opener, onMade: act)),
            icon: const Icon(CupertinoIcons.add), label: const Text('Add a device')),
        ])),
    ]);
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.client, required this.act});

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
      leading: Icon(DeviceKind.of(device['reaches'])!.icon, color: on ? brand.accentText : brand.muted),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${_reachLines[device['reaches']]}$added'),
      trailing: on
        ? TextButton(onPressed: () => _turnOff(context, name), style: quietButton(context), child: const Text('Turn off'))
        : const BrandTag('Off'),
    );
  }

  Future<void> _turnOff(BuildContext context, String name) async {
    final sure = await confirm(context, title: 'Turn off $name?', action: 'Turn off',
      body: 'Its key stops working at once. What it sent stays. To use the device again, add it again.');
    if (!sure) return;
    await act(() => client.post('devices/off', {'id': device['id']}));
  }
}

/// *Add a device*: a kind and a name, then the new key's steps. The key shows only in this dialog: closing it forgets
/// the key, and the page never shows it again. Closes with true once a key was made; [onMade] runs as the key is made.
class AddDeviceDialog extends StatefulWidget {
  const AddDeviceDialog({super.key, required this.client, this.opener, this.onMade});

  final SpaceClient client;
  final Opener? opener;
  final Future<void> Function()? onMade;

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  var _kind = DeviceKind.phone;
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
      final name = _name.text.trim().isEmpty ? _kind.name : _name.text.trim();
      final made = await widget.client.post('devices', {'name': name, 'reaches': _kind.reaches});
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
      title: Text(made == null ? 'Add a device' : 'Connect ${made['name']}'),
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
    const Text('Each device gets its own key, and you can turn it off alone. A device key only adds data. An API key also '
      'reads notes.'),
    const SizedBox(height: 16),
    SegmentedButton<DeviceKind>(
      segments: [for (final kind in DeviceKind.values) ButtonSegment(value: kind, label: Text(kind.label))],
      selected: {_kind}, showSelectedIcon: false,
      onSelectionChanged: (picked) => setState(() => _kind = picked.single),
    ),
    const SizedBox(height: 16),
    TextField(controller: _name, maxLength: 60,
      decoration: InputDecoration(labelText: 'Name', hintText: _kind.name, border: const OutlineInputBorder())),
    if (_problem case final problem?) Problem(problem),
  ];

  List<Widget> _steps(Map<String, dynamic> made) {
    final qr = '${made['qr']}';
    final key = '${made['key']}';
    final open = widget.opener ?? openInBrowser;
    Widget link(String label, String address) =>
      Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => open(Uri.parse(address)), child: Text(label)));
    return [
      const Note('Relay Everything shows this key once. Do these steps before you close this window.'),
      ...switch (DeviceKind.of(made['reaches']) ?? _kind) {
        DeviceKind.phone => [
          const Text('1. Install the Relay Everything app on your phone.'),
          link('How to install the app', installPage),
          const Text('2. In the app, open Settings and tap Sign in to Relay Everything. Then tap Scan a key and scan this code:'),
          const SizedBox(height: 8),
          // White with a wide margin, as a phone's camera needs.
          Center(child: QrImageView(data: qr, size: 240, padding: const EdgeInsets.all(20), backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M, semanticsLabel: 'QR code for ${made['name']}')),
          const SizedBox(height: 8),
          const Text('3. No camera? Copy the code and paste it in the app:'),
          CopyField(text: qr, label: 'The code', button: 'Copy the code'),
        ],
        DeviceKind.claude => [
          const Text('1. Copy the connect code:'),
          CopyField(text: qr, label: 'The connect code', button: 'Copy the connect code'),
          const Text('2. In Claude Code, add the plugin:'),
          const CopyField(text: '/plugin marketplace add matthewwong525/RelayEverything', label: 'Add the marketplace'),
          const CopyField(text: '/plugin install relay@relay', label: 'Install the plugin'),
          const Text('3. Paste the connect code when Claude Code asks. The key can only add chats.'),
        ],
        DeviceKind.api => [
          const Text("1. Copy the key into your script or service's secret store. Never put it in a file you share:"),
          CopyField(text: key, label: 'The key', button: 'Copy the key'),
          const Text('2. Send it as a header. This call names the key and reads no data:'),
          CopyField(text: 'curl -H "Authorization: Bearer $key" ${made['api'] ?? '<your-relay-server>/v1'}/me',
            label: 'The example', button: 'Copy the example'),
          const Text('3. The key reads and adds notes. It can not change or delete them.'),
          link("Read the web API's routes", apiDocs),
        ],
      },
    ];
  }
}
