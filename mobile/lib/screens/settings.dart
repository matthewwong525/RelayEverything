import 'package:flutter/material.dart';

import '../relay.dart';
import 'connect.dart';

/// Each switch acts at once and asks for its permission only when turned on. Sending is off until the person turns it
/// on; health and location history sit under it and work only with it.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.relay, this.scanner});

  final Relay relay;
  final Scanner? scanner;

  Future<void> _apply(BuildContext context, Future<String?> change) async {
    final problem = await change;
    if (problem != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) {
          final settings = relay.settings;
          final sending = settings.sending;
          return ListView(children: [
            SwitchListTile(
              title: const Text('Pin notes to where I am'),
              subtitle: const Text('Each typed note keeps where you were. It works with no signal.'),
              value: settings.pinNotes,
              onChanged: (on) => _apply(context, relay.setPinNotes(on)),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Send to your Relay server'),
              subtitle: const Text('Your server can pass notes to your own database and your AI. Ring notes from the Pebble app '
                'come through it. Off: nothing leaves this phone.'),
              value: sending,
              onChanged: (on) => on ? _startSending(context) : _stopSending(context),
            ),
            SwitchListTile(
              title: const Text('Health: steps, heart rate, sleep, workouts'),
              subtitle: const Text('Sends them every hour.'),
              value: settings.health,
              onChanged: sending ? (on) => _apply(context, relay.setHealth(on)) : null,
            ),
            SwitchListTile(
              title: const Text('Location history'),
              subtitle: const Text('Keeps a point each 100 m you move, so ring notes get a place too.'),
              value: settings.history,
              onChanged: sending ? (on) => _apply(context, relay.setHistory(on)) : null,
            ),
            if (relay.connected) ...[
              ListTile(
                title: const Text('Server'),
                subtitle: Text(relay.server ?? ''),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editServer(context),
              ),
              ListTile(
                title: const Text('Disconnect this phone'),
                subtitle: const Text('Removes the key from this phone and turns sending off. Your notes stay here.'),
                onTap: () => _disconnect(context),
              ),
            ],
          ]);
        },
      ),
    );
  }

  /// Connects a key the first time, then asks about the notes that never went, then turns sending on.
  Future<void> _startSending(BuildContext context) async {
    if (!relay.connected) {
      final connected = await Navigator.of(context).push(MaterialPageRoute<bool>(
        builder: (_) => ConnectScreen(relay: relay, scanner: scanner)));
      if (connected != true || !context.mounted) return;
    }
    final earlier = await relay.earlierNotes();
    var sendEarlier = false;
    if (earlier > 0) {
      if (!context.mounted) return;
      final choice = await showDialog<bool>(context: context, builder: (context) => _EarlierDialog(count: earlier));
      if (choice == null) return;
      sendEarlier = choice;
    }
    if (context.mounted) await _apply(context, relay.startSending(sendEarlier: sendEarlier));
  }

  Future<void> _stopSending(BuildContext context) async {
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Stop sending?'),
      content: const Text('New notes stay on this phone. Notes already on your Relay server stay there. Health and location stop.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop sending')),
      ],
    ));
    if (sure == true) await relay.stopSending();
  }

  Future<void> _editServer(BuildContext context) async {
    final address = await showDialog<String>(context: context, builder: (context) => _ServerDialog(server: relay.server));
    if (address != null && context.mounted) await _apply(context, relay.setServer(address));
  }

  Future<void> _disconnect(BuildContext context) async {
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Disconnect this phone?'),
      content: const Text('Sending turns off. You need a new key to send again.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
      ],
    ));
    if (sure == true) await relay.disconnect();
  }
}

/// Asks whether the notes kept only on this phone go too. *Only new notes* keeps no record, so the next turn-on asks
/// again.
class _EarlierDialog extends StatelessWidget {
  const _EarlierDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(count == 1 ? 'Send your earlier note too?' : 'Send your $count earlier notes too?'),
      content: Text('${count == 1 ? 'It was' : 'They were'} only on this phone. New notes go to your Relay server from now on.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Only new notes')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(count == 1 ? 'Send it' : 'Send them')),
      ],
    );
  }
}

/// Owns its text field, so the field lives until the dialog's closing animation ends.
class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.server});

  final String? server;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _text = TextEditingController(text: widget.server);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server'),
      content: TextField(controller: _text, keyboardType: TextInputType.url, autofocus: true,
        decoration: const InputDecoration(helperText: 'Use a preview address to try a change.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('Save')),
      ],
    );
  }
}
