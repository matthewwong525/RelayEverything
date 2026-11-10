import 'package:flutter/material.dart';

import '../screens/folder.dart' show Group, Opener, openInBrowser;
import 'settings_parts.dart';
import 'space.dart';

/// *AI apps*: the AI connector's address to add to Claude or ChatGPT, and the apps connected to it, each disconnected
/// after a confirm. A server with no connector answers 503, and the page says so.
class AiAppsPage extends StatelessWidget {
  const AiAppsPage({super.key, required this.client, this.opener});

  final SpaceClient client;
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    return SettingsBody(title: 'AI apps', children: [SpaceView<Map<String, dynamic>>(
      what: 'The AI apps', load: () => client.get('ai-apps'),
      refused: (refused) => refused.status == 503 ? const Note('The AI connector is not set up on this server.') : null,
      builder: (context, value, act) {
        final apps = listOf(value, 'apps');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Ask Claude or ChatGPT about your notes, health and places, or tell it to add a note. In the app, add a '
            'custom connector with this address, then sign in.'),
          const SizedBox(height: 8),
          CopyField(text: '${value['address']}', label: "The connector's address"),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Note('The same sign-in opens the web API, for your own scripts and services.'),
            TextButton(onPressed: () => (opener ?? openInBrowser)(Uri.parse(apiDocs)), child: const Text('Connect a service')),
          ]),
          const SizedBox(height: 8),
          Text('Connected apps · ${apps.length} connected', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (apps.isEmpty) const Note('No AI app connected yet.')
          else Group(children: [for (final app in apps) ListTile(
            title: Text('${app['name']}'),
            subtitle: app['connectedAt'] is int ? Text('Connected ${whenOf(app['connectedAt'] as int)}') : null,
            trailing: TextButton(onPressed: () => _disconnect(context, app, act), child: const Text('Disconnect')),
          )]),
        ]);
      })]);
  }

  Future<void> _disconnect(BuildContext context, Map<String, dynamic> app, Act act) async {
    if (!await confirm(context, title: 'Disconnect ${app['name']}?', action: 'Disconnect',
      body: 'It can not read or add to Relay Everything any more. To use it again, connect it again from the app.')) {
      return;
    }
    await act(() => client.post('ai-apps-disconnect', {'id': app['id']}));
  }
}
