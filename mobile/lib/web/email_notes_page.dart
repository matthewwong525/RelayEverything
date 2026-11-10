import 'package:flutter/material.dart';

import '../brand.dart';
import 'settings_parts.dart';
import 'space.dart';

/// *Email notes*: the person's own notes address, which makes a note of any mail, with *New address*, and the shared
/// address for their sign-in email. Settings lists it only when the server takes email.
class EmailNotesPage extends StatelessWidget {
  const EmailNotesPage({super.key, required this.client});

  final SpaceClient client;

  Future<Map<String, dynamic>> _load() async {
    final email = (await client.get('inbox'))['email'];
    return email is Map<String, dynamic> ? email : const {};
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBody(title: 'Email notes', children: [SpaceView<Map<String, dynamic>>(
      what: 'Your notes address', load: _load,
      builder: (context, email, act) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CopyField(text: '${email['address']}', label: 'Your notes address'),
        const Note('Anything sent here becomes a note.'),
        Align(alignment: Alignment.centerLeft, child: TextButton(
          onPressed: () => _newAddress(context, act), style: quietButton(context), child: const Text('New address'))),
        Note('You can also write to ${email['shared']} from your sign-in email.'),
        const Note('Email is not sealed on the way. Do not send health or location details this way.'),
      ]))]);
  }

  Future<void> _newAddress(BuildContext context, Act act) async {
    if (!await confirm(context, title: 'Make a new address?', action: 'New address',
      body: 'Mail to your old address stops making notes at once. Change every mail rule and contact that uses it.')) {
      return;
    }
    await act(() => client.post('inbox/address'));
  }
}
